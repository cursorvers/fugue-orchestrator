#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
repo="cursorvers/fugue-orchestrator"
apply="false"
provider="codex"
assist_provider="claude"
add_tutti="true"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/create-kernel-googleworkspace-issues.sh [options]

Create the Kernel Google Workspace issue set (Issues 1-5) from the ready docs.

Options:
  --repo <owner/repo>        Target repo (default: cursorvers/fugue-orchestrator)
  --apply                    Actually create issues via `gh issue create`
  --dry-run                  Print the planned `gh` actions (default)
  --provider <codex|claude>  Main orchestrator provider body hint (default: codex)
  --assist <claude|codex|none>
                             Assist orchestrator provider body hint (default: claude)
  --no-tutti                 Do not add the `tutti` label after issue creation
  -h, --help                 Show help.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

normalize_provider() {
  local value
  value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "${value}" in
    codex|claude|none)
      printf '%s' "${value}"
      ;;
    *)
      fail "invalid provider: ${1:-}"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --apply)
      apply="true"
      shift
      ;;
    --dry-run)
      apply="false"
      shift
      ;;
    --provider)
      provider="$(normalize_provider "${2:-}")"
      [[ "${provider}" != "none" ]] || fail "main provider cannot be none"
      shift 2
      ;;
    --assist)
      assist_provider="$(normalize_provider "${2:-}")"
      shift 2
      ;;
    --no-tutti)
      add_tutti="false"
      shift
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

extract_title() {
  local file="$1"
  awk '
    found && /^`/ { gsub(/^`|`$/, ""); print; exit }
    /^## Suggested Title$/ { found=1 }
  ' "${file}"
}

extract_body() {
  local file="$1"
  awk '
    /^## Paste-Ready Body$/ { in_section=1; next }
    in_section && /^```md$/ { capture=1; next }
    capture && /^```$/ { exit }
    capture { print }
  ' "${file}"
}

build_body() {
  local ready_file="$1"
  local paste_body
  paste_body="$(extract_body "${ready_file}")"
  [[ -n "${paste_body}" ]] || fail "could not extract issue body from ${ready_file#${ROOT_DIR}/}"

  cat <<EOF
${paste_body}

## Target repo


${repo}

## Orchestrator provider
${provider}

## Assist orchestrator provider
${assist_provider}

## Mode
implement

## Implement confirmation
confirmed
EOF
}

ensure_label() {
  local label="$1"
  local description="$2"
  local color="$3"
  gh label create "${label}" --repo "${repo}" --description "${description}" --color "${color}" >/dev/null 2>&1 || true
}

create_issue() {
  local title="$1"
  local body_file="$2"
  local url issue_num

  ensure_label "implement" "Implementation intent (provider-agnostic)" "1D76DB"
  ensure_label "implement-confirmed" "Human has explicitly confirmed implementation execution" "0E8A16"
  ensure_label "orchestrator:${provider}" "Requested orchestrator profile for Tutti routing" "5319E7"
  ensure_label "orchestrator-assist:${assist_provider}" "Requested assist orchestrator profile for Tutti routing" "0052CC"

  url="$(gh issue create \
    --repo "${repo}" \
    --title "${title}" \
    --label "fugue-task,implement,implement-confirmed,orchestrator:${provider},orchestrator-assist:${assist_provider}" \
    --body-file "${body_file}")"

  issue_num="${url##*/}"
  if [[ "${add_tutti}" == "true" ]]; then
    gh issue edit "${issue_num}" --repo "${repo}" --add-label "tutti" >/dev/null
  fi

  printf '%s\t%s\n' "${issue_num}" "${title}"
}

issue_files=(
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-1-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-2-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-3-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-4-ready.md"
  "${ROOT_DIR}/docs/kernel-googleworkspace-issue-5-ready.md"
)

for file in "${issue_files[@]}"; do
  [[ -f "${file}" ]] || fail "missing ready doc: ${file#${ROOT_DIR}/}"
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

if [[ "${apply}" == "true" ]]; then
  require_cmd gh
  gh auth status >/dev/null 2>&1 || fail "gh auth status failed; run gh auth login first"
fi

for idx in "${!issue_files[@]}"; do
  file="${issue_files[${idx}]}"
  title="$(extract_title "${file}")"
  [[ -n "${title}" ]] || fail "could not extract issue title from ${file#${ROOT_DIR}/}"
  body_file="${tmp_dir}/issue-$((idx + 1)).md"
  build_body "${file}" > "${body_file}"

  if [[ "${apply}" == "true" ]]; then
    create_issue "${title}" "${body_file}"
  else
    printf 'ISSUE %s\n' "$((idx + 1))"
    printf 'repo: %s\n' "${repo}"
    printf 'title: %s\n' "${title}"
    printf 'labels: %s\n' "fugue-task,implement,implement-confirmed,orchestrator:${provider},orchestrator-assist:${assist_provider}$( [[ "${add_tutti}" == "true" ]] && printf ',tutti' )"
    printf 'body_file: %s\n' "${body_file}"
    echo '---'
  fi
done
