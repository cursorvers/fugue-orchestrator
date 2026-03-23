#!/usr/bin/env bash
set -euo pipefail

REPO="cursorvers/fugue-orchestrator"

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
  scripts/local/create-fugue-issue.sh --title <title> --body-file <path>

Creates a FUGUE issue with the required labels. If an exact-title duplicate
already exists, prints the existing issue URL instead.
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

find_duplicate_issue_url() {
  local title="$1"
  local number found_title url

  while IFS=$'\t' read -r number found_title url; do
    [[ -n "${number}" ]] || continue
    if [[ "${found_title}" == "${title}" ]]; then
      printf '%s\n' "${url}"
      return 0
    fi
  done < <(
    gh api search/issues \
      -f q="repo:${REPO} is:issue in:title ${title}" \
      -f per_page=100 \
      --template '{{range .items}}{{.number}}{{"\t"}}{{.title}}{{"\t"}}{{.html_url}}{{"\n"}}{{end}}'
  )

  return 1
}

TITLE=""
BODY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body-file)
      BODY_FILE="${2:-}"
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

[[ -n "${TITLE}" ]] || fail "--title is required"
[[ -n "${BODY_FILE}" ]] || fail "--body-file is required"
[[ -f "${BODY_FILE}" ]] || fail "body file not found: ${BODY_FILE}"

require_cmd gh
require_gh_auth
ensure_required_labels_exist

duplicate_url="$(find_duplicate_issue_url "${TITLE}" || true)"
if [[ -n "${duplicate_url}" ]]; then
  echo "Duplicate issue already exists for title: ${TITLE}" >&2
  printf '%s\n' "${duplicate_url}"
  exit 0
fi

create_cmd=(
  gh issue create
  --repo "${REPO}"
  --title "${TITLE}"
  --body-file "${BODY_FILE}"
)

for label in "${REQUIRED_LABELS[@]}"; do
  create_cmd+=(--label "${label}")
done

issue_url="$("${create_cmd[@]}")"
printf '%s\n' "${issue_url}"
