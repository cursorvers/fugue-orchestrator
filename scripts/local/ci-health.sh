#!/usr/bin/env bash
set -euo pipefail

REPO="cursorvers/fugue-orchestrator"
LIMIT=50

usage() {
  cat <<'EOF'
Usage:
  scripts/local/ci-health.sh [--limit <count>]

Shows GitHub Actions run health stats for the most recent runs in the repo.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

require_gh_auth() {
  gh auth status -h github.com >/dev/null 2>&1 || fail "gh auth is not ready; run gh auth login -h github.com"
}

is_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

percent() {
  local count="$1"
  local total="$2"
  if [[ "${total}" -eq 0 ]]; then
    printf '0'
  else
    printf '%s' "$(( count * 100 / total ))"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

is_positive_integer "${LIMIT}" || fail "--limit must be a positive integer"

require_cmd gh
require_gh_auth

total=0
success=0
failure=0
skipped=0
cancelled=0
in_progress=0
other=0

while IFS=$'\t' read -r status conclusion; do
  [[ -n "${status}" ]] || continue
  total=$((total + 1))

  if [[ "${status}" != "completed" ]]; then
    in_progress=$((in_progress + 1))
    continue
  fi

  case "${conclusion}" in
    success)
      success=$((success + 1))
      ;;
    failure|startup_failure|timed_out|action_required|stale)
      failure=$((failure + 1))
      ;;
    skipped)
      skipped=$((skipped + 1))
      ;;
    cancelled)
      cancelled=$((cancelled + 1))
      ;;
    *)
      other=$((other + 1))
      ;;
  esac
done < <(
  gh run list \
    --repo "${REPO}" \
    --limit "${LIMIT}" \
    --json status,conclusion \
    --template '{{range .}}{{.status}}{{"\t"}}{{if .conclusion}}{{.conclusion}}{{end}}{{"\n"}}{{end}}'
)

printf 'repo: %s\n' "${REPO}"
printf 'runs inspected: %s\n' "${total}"
printf 'success: %s (%s%%)\n' "${success}" "$(percent "${success}" "${total}")"
printf 'failure: %s (%s%%)\n' "${failure}" "$(percent "${failure}" "${total}")"
printf 'skipped: %s (%s%%)\n' "${skipped}" "$(percent "${skipped}" "${total}")"
printf 'cancelled: %s (%s%%)\n' "${cancelled}" "$(percent "${cancelled}" "${total}")"
printf 'in_progress: %s (%s%%)\n' "${in_progress}" "$(percent "${in_progress}" "${total}")"
printf 'other: %s (%s%%)\n' "${other}" "$(percent "${other}" "${total}")"
