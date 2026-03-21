#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRELIGHT_SCRIPT="${ROOT_DIR}/scripts/harness/googleworkspace-preflight-enrich.sh"
ADAPTER="${ROOT_DIR}/scripts/lib/googleworkspace-cli-adapter.sh"

issue_number="9102"
issue_title="Kernel Google Workspace Phase 2 Mailbox"
out_dir="${ROOT_DIR}/.fugue/kernel-googleworkspace-workset/phase2-mailbox-run"
run_dir="${out_dir}/run"
report_path="${out_dir}/phase2-mailbox-report.md"
execute="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/run-kernel-googleworkspace-phase2-mailbox.sh [options]

Prepare or execute the Phase 2 Kernel Google Workspace mailbox readonly lane
for `weekly-digest` and `gmail-triage`.

Default behavior is local-safe: print the exact command and target files
without executing any networked Workspace calls.

Options:
  --issue-number <n>         Issue number context (default: 9102)
  --issue-title <text>       Issue title context
  --out-dir <path>           Output directory
  --execute                  Actually run the preflight script
  --prepare                  Print the command only (default)
  -h, --help                 Show help.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_positive_int() {
  local raw="${1:-}"
  local label="${2:-value}"
  [[ "${raw}" =~ ^[0-9]+$ ]] || fail "${label} must be a positive integer"
  (( raw > 0 )) || fail "${label} must be greater than zero"
  printf '%s' "${raw}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-number)
      issue_number="$(require_positive_int "${2:-}" "--issue-number")"
      shift 2
      ;;
    --issue-title)
      issue_title="${2:-}"
      shift 2
      ;;
    --out-dir)
      out_dir="${2:-}"
      shift 2
      ;;
    --execute)
      execute="true"
      shift
      ;;
    --prepare)
      execute="false"
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

run_dir="${out_dir%/}/run"
report_path="${out_dir%/}/phase2-mailbox-report.md"
mkdir -p "${out_dir}" "${run_dir}"

cmd=(
  env
  ISSUE_NUMBER="${issue_number}"
  ISSUE_TITLE="${issue_title}"
  ISSUE_BODY="Phase 2 mailbox readonly evidence validation for weekly-digest and gmail-triage."
  WORKSPACE_ACTIONS="weekly-digest,gmail-triage"
  WORKSPACE_DOMAINS="calendar,gmail,drive"
  WORKSPACE_REASON="Kernel Phase 2 mailbox readonly evidence validation"
  WORKSPACE_SUGGESTED_PHASES="preflight-enrich,recovery-rehydrate"
  REPORT_PATH="${report_path}"
  OUT_DIR="${out_dir}"
  RUN_DIR="${run_dir}"
  ADAPTER="${ADAPTER}"
  bash
  "${PRELIGHT_SCRIPT}"
)

if [[ "${execute}" != "true" ]]; then
  printf 'mode=prepare\n'
  printf 'report=%s\n' "${report_path#${ROOT_DIR}/}"
  printf 'run_dir=%s\n' "${run_dir#${ROOT_DIR}/}"
  printf 'note=%s\n' 'mailbox flows prefer GOOGLE_WORKSPACE_USER_CREDENTIALS_FILE/JSON when supplied'
  printf 'command='
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

"${cmd[@]}"
