#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${ROOT_DIR}/config/orchestration/sovereign-adapters.json"

repo=""
issue_number=""
dispatch_nonce=""
trust_subject=""
vote_instruction_b64=""
allow_processing_rerun="false"
dry_run="false"
workflow_file="fugue-tutti-caller.yml"

usage() {
  cat <<'EOF'
Usage:
  scripts/harness/fugue-bridge-handoff.sh --repo <owner/repo> --issue-number <n> --dispatch-nonce <nonce> [options]

Options:
  --repo <owner/repo>              Target repository
  --issue-number <n>               Issue number
  --dispatch-nonce <nonce>         Unique nonce for workflow dispatch
  --trust-subject <login>          Optional trusted actor login
  --vote-instruction-b64 <value>   Optional base64-encoded /vote instruction
  --allow-processing-rerun         Allow rerun while processing label exists
  --dry-run                        Print the resolved gh command without executing it
  -h, --help                       Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --issue-number)
      issue_number="${2:-}"
      shift 2
      ;;
    --dispatch-nonce)
      dispatch_nonce="${2:-}"
      shift 2
      ;;
    --trust-subject)
      trust_subject="${2:-}"
      shift 2
      ;;
    --vote-instruction-b64)
      vote_instruction_b64="${2:-}"
      shift 2
      ;;
    --allow-processing-rerun)
      allow_processing_rerun="true"
      shift 1
      ;;
    --dry-run)
      dry_run="true"
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${repo}" || -z "${issue_number}" || -z "${dispatch_nonce}" ]]; then
  echo "Error: --repo, --issue-number, and --dispatch-nonce are required." >&2
  usage >&2
  exit 2
fi

if [[ ! -f "${MANIFEST}" ]]; then
  echo "Error: sovereign adapter manifest not found: ${MANIFEST}" >&2
  exit 1
fi

if ! jq -e '.adapters[] | select(.id == "fugue-bridge") | .provider == "legacy-fugue" and .class == "legacy-bridge" and .availability == "rollback-ready"' "${MANIFEST}" >/dev/null 2>&1; then
  echo "Error: fugue-bridge adapter is not rollback-ready in ${MANIFEST}" >&2
  exit 1
fi

dispatch_cmd=(
  gh workflow run "${workflow_file}"
  --repo "${repo}"
  -f issue_number="${issue_number}"
  -f dispatch_nonce="${dispatch_nonce}"
  -f handoff_target="fugue-bridge"
)

trust_subject="$(printf '%s' "${trust_subject}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${trust_subject}" ]]; then
  dispatch_cmd+=(-f trust_subject="${trust_subject}")
fi
vote_instruction_b64="$(printf '%s' "${vote_instruction_b64}" | tr -d '\n\r[:space:]')"
if [[ -n "${vote_instruction_b64}" ]]; then
  dispatch_cmd+=(-f vote_instruction_b64="${vote_instruction_b64}")
fi
if [[ "${allow_processing_rerun}" == "true" ]]; then
  dispatch_cmd+=(-f allow_processing_rerun="true")
fi

if [[ "${dry_run}" == "true" ]]; then
  printf '%q ' "${dispatch_cmd[@]}"
  printf '\n'
  exit 0
fi

"${dispatch_cmd[@]}" >/dev/null
echo "handoff_target=fugue-bridge"
echo "workflow_file=${workflow_file}"
