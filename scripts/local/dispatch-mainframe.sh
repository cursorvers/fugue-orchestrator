#!/usr/bin/env bash
set -euo pipefail

REPO="cursorvers/fugue-orchestrator"
WORKFLOW_FILE="fugue-tutti-caller.yml"
POLL_ATTEMPTS=18
POLL_INTERVAL_SECONDS=5

REQUIRED_LABELS=(
  "fugue-task"
  "tutti"
  "implement"
  "implement-confirmed"
  "orchestrator:codex"
  "orchestrator-assist:claude"
)

usage() {
  cat <<'EOF'
Usage:
  scripts/local/dispatch-mainframe.sh <issue_number>

Adds the required FUGUE labels to an issue, dispatches the Mainframe workflow,
and prints the run URL.
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

label_color() {
  case "$1" in
    "fugue-task") echo "0E8A16" ;;
    "tutti") echo "B60205" ;;
    "implement") echo "1D76DB" ;;
    "implement-confirmed") echo "0E8A16" ;;
    "orchestrator:codex") echo "5319E7" ;;
    "orchestrator-assist:claude") echo "0052CC" ;;
    *) fail "unknown label color for: $1" ;;
  esac
}

label_description() {
  case "$1" in
    "fugue-task") echo "Task routed through Fugue orchestration" ;;
    "tutti") echo "Dispatch through the Tutti mainframe workflow" ;;
    "implement") echo "Implementation intent (provider-agnostic)" ;;
    "implement-confirmed") echo "Human has explicitly confirmed implementation execution" ;;
    "orchestrator:codex") echo "Requested main orchestrator provider" ;;
    "orchestrator-assist:claude") echo "Requested assist orchestrator provider" ;;
    *) fail "unknown label description for: $1" ;;
  esac
}

join_by_comma() {
  local IFS=","
  printf '%s' "$*"
}

ensure_required_labels_exist() {
  local existing_labels label
  existing_labels="$(gh label list --repo "${REPO}" --limit 200 --json name --template '{{range .}}{{.name}}{{"\n"}}{{end}}')"

  for label in "${REQUIRED_LABELS[@]}"; do
    if ! printf '%s\n' "${existing_labels}" | grep -Fxq "${label}"; then
      gh label create "${label}" \
        --repo "${REPO}" \
        --color "$(label_color "${label}")" \
        --description "$(label_description "${label}")" >/dev/null
      existing_labels="${existing_labels}"$'\n'"${label}"
    fi
  done
}

latest_workflow_dispatch_run_id() {
  local line run_id event path actor url
  gh api "repos/${REPO}/actions/runs?per_page=100" \
    --template '{{range .workflow_runs}}{{.id}}{{"\t"}}{{.event}}{{"\t"}}{{.path}}{{"\t"}}{{if .actor}}{{.actor.login}}{{end}}{{"\t"}}{{.html_url}}{{"\n"}}{{end}}' \
  | while IFS=$'\t' read -r run_id event path actor url; do
      [[ -n "${run_id}" ]] || continue
      [[ "${event}" == "workflow_dispatch" ]] || continue
      case "${path}" in
        */"${WORKFLOW_FILE}"|"${WORKFLOW_FILE}")
          printf '%s\n' "${run_id}"
          return 0
          ;;
      esac
    done
}

wait_for_dispatched_run_url() {
  local baseline_id="$1"
  local expected_actor="$2"
  local attempt run_id event path actor url

  for ((attempt=1; attempt<=POLL_ATTEMPTS; attempt++)); do
    while IFS=$'\t' read -r run_id event path actor url; do
      [[ -n "${run_id}" ]] || continue
      [[ "${run_id}" =~ ^[0-9]+$ ]] || continue
      [[ "${run_id}" -gt "${baseline_id}" ]] || continue
      [[ "${event}" == "workflow_dispatch" ]] || continue
      case "${path}" in
        */"${WORKFLOW_FILE}"|"${WORKFLOW_FILE}") ;;
        *) continue ;;
      esac
      if [[ -n "${expected_actor}" && "${actor}" != "${expected_actor}" ]]; then
        continue
      fi
      printf '%s\n' "${url}"
      return 0
    done < <(
      gh api "repos/${REPO}/actions/runs?per_page=100" \
        --template '{{range .workflow_runs}}{{.id}}{{"\t"}}{{.event}}{{"\t"}}{{.path}}{{"\t"}}{{if .actor}}{{.actor.login}}{{end}}{{"\t"}}{{.html_url}}{{"\n"}}{{end}}'
    )
    sleep "${POLL_INTERVAL_SECONDS}"
  done

  return 1
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ISSUE_NUMBER="$1"
is_positive_integer "${ISSUE_NUMBER}" || fail "issue_number must be a positive integer"

require_cmd gh
require_gh_auth

issue_url="$(gh issue view "${ISSUE_NUMBER}" --repo "${REPO}" --json url --template '{{.url}}')"
[[ -n "${issue_url}" ]] || fail "issue not found: ${ISSUE_NUMBER}"

ensure_required_labels_exist

label_csv="$(join_by_comma "${REQUIRED_LABELS[@]}")"
gh issue edit "${ISSUE_NUMBER}" --repo "${REPO}" --add-label "${label_csv}" >/dev/null

baseline_run_id="$(latest_workflow_dispatch_run_id || true)"
baseline_run_id="${baseline_run_id:-0}"

actor_login="$(gh api user --template '{{.login}}')"
dispatch_nonce="local-dispatch-${ISSUE_NUMBER}-$(date +%s)-$$"

gh workflow run "${WORKFLOW_FILE}" \
  --repo "${REPO}" \
  -f issue_number="${ISSUE_NUMBER}" \
  -f dispatch_nonce="${dispatch_nonce}" >/dev/null

run_url="$(wait_for_dispatched_run_url "${baseline_run_id}" "${actor_login}" || true)"
[[ -n "${run_url}" ]] || fail "workflow dispatched for issue ${ISSUE_NUMBER}, but no run URL was found after polling"

printf '%s\n' "${run_url}"
