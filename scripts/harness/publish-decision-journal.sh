#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common-utils.sh"

repo="${GITHUB_REPOSITORY:-}"
sha="${GITHUB_SHA:-}"
before_sha="${GITHUB_EVENT_BEFORE:-}"
ref_name="${GITHUB_REF_NAME:-unknown}"
summary_file="${GITHUB_STEP_SUMMARY:-}"

if [[ -z "${repo}" || -z "${sha}" ]]; then
  echo "GITHUB_REPOSITORY and GITHUB_SHA are required" >&2
  exit 1
fi

append_summary() {
  local line="${1:-}"
  printf '%s\n' "${line}"
  if [[ -n "${summary_file}" ]]; then
    printf '%s\n' "${line}" >> "${summary_file}"
  fi
}

ensure_status_issue() {
  local status_issue
  status_issue="$(fugue_gh_retry 4 gh issue list --repo "${repo}" --state open --label "fugue-status" --limit 1 --json number --jq '.[0].number // empty' || true)"
  if [[ -n "${status_issue}" ]]; then
    printf '%s\n' "${status_issue}"
    return 0
  fi

  fugue_gh_retry 4 gh label create "fugue-status" \
    --repo "${repo}" \
    --description "Status reporting thread for FUGUE orchestration" \
    --color "1D76DB" >/dev/null 2>&1 || true

  local status_issue_url
  status_issue_url="$(
    fugue_gh_retry 4 gh issue create --repo "${repo}" \
      --title "FUGUE Status Thread" \
      --label "fugue-status" \
      --body "Automated status and mobile progress reports are posted here."
  )"
  printf '%s\n' "${status_issue_url##*/}"
}

list_changed_files() {
  if [[ -n "${before_sha}" && ! "${before_sha}" =~ ^0+$ ]] && git cat-file -e "${before_sha}^{commit}" 2>/dev/null; then
    git diff --name-only "${before_sha}" "${sha}" -- \
      docs/ \
      apps/happy-web/ \
      prototypes/happy-mobile-web/
  else
    git show --pretty="" --name-only "${sha}" -- \
      docs/ \
      apps/happy-web/ \
      prototypes/happy-mobile-web/
  fi
}

commit_title="$(git log -1 --pretty=%s "${sha}")"
changed_files="$(list_changed_files | sed '/^$/d' | head -n 20)"

if [[ -z "${changed_files}" ]]; then
  append_summary "No tracked design/app files changed; skipping decision journal."
  exit 0
fi

status_issue="$(ensure_status_issue)"
comment_file="$(mktemp)"

{
  printf '## Kernel Decision Journal\n\n'
  printf -- '- branch: `%s`\n' "${ref_name}"
  printf -- '- commit: `%s`\n' "${sha}"
  printf -- '- title: `%s`\n' "${commit_title}"
  printf -- '- workflow: `%s/%s/actions/runs/%s`\n' "${GITHUB_SERVER_URL:-https://github.com}" "${repo}" "${GITHUB_RUN_ID:-}"
  printf '\n### Changed files\n'
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    printf -- '- `%s`\n' "${file}"
  done <<< "${changed_files}"
} > "${comment_file}"

fugue_gh_retry 4 gh issue comment "${status_issue}" --repo "${repo}" --body-file "${comment_file}" >/dev/null

append_summary "Posted decision journal to fugue-status issue #${status_issue}."
append_summary "Changed files:"
while IFS= read -r file; do
  [[ -z "${file}" ]] && continue
  append_summary "- ${file}"
done <<< "${changed_files}"
