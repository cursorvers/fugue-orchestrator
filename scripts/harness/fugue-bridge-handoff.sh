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
requested_execution_mode=""
subscription_offline_policy_override=""
implement_request=""
implement_confirmed=""
vote_command="false"
intake_source=""
execution_mode_override="auto"
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
  --requested-execution-mode <v>   Resolved handoff mode (review|implement)
  --subscription-offline-policy-override <v>
                                   Optional offline policy override (hold|continuity)
  --implement-request <bool>       Resolved implementation intent snapshot
  --implement-confirmed <bool>     Resolved implementation confirmation snapshot
  --vote-command <bool>            True when the handoff originated from `/vote`
  --intake-source <value>          Intake source marker for audit/policy
  --execution-mode-override <v>    Execution policy override (auto|primary|backup-safe|backup-heavy)
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
    --requested-execution-mode)
      requested_execution_mode="${2:-}"
      shift 2
      ;;
    --subscription-offline-policy-override)
      subscription_offline_policy_override="${2:-}"
      shift 2
      ;;
    --implement-request)
      implement_request="${2:-}"
      shift 2
      ;;
    --implement-confirmed)
      implement_confirmed="${2:-}"
      shift 2
      ;;
    --vote-command)
      vote_command="${2:-}"
      shift 2
      ;;
    --intake-source)
      intake_source="${2:-}"
      shift 2
      ;;
    --execution-mode-override)
      execution_mode_override="${2:-}"
      shift 2
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
requested_execution_mode="$(printf '%s' "${requested_execution_mode}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${requested_execution_mode}" == "review" || "${requested_execution_mode}" == "implement" ]]; then
  dispatch_cmd+=(-f requested_execution_mode="${requested_execution_mode}")
fi
subscription_offline_policy_override="$(printf '%s' "${subscription_offline_policy_override}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${subscription_offline_policy_override}" == "hold" || "${subscription_offline_policy_override}" == "continuity" ]]; then
  dispatch_cmd+=(-f subscription_offline_policy_override="${subscription_offline_policy_override}")
fi
implement_request="$(printf '%s' "${implement_request}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${implement_request}" == "true" || "${implement_request}" == "false" ]]; then
  dispatch_cmd+=(-f implement_request="${implement_request}")
fi
implement_confirmed="$(printf '%s' "${implement_confirmed}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${implement_confirmed}" == "true" || "${implement_confirmed}" == "false" ]]; then
  dispatch_cmd+=(-f implement_confirmed="${implement_confirmed}")
fi
vote_command="$(printf '%s' "${vote_command}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${vote_command}" == "true" ]]; then
  dispatch_cmd+=(-f vote_command="true")
fi
intake_source="$(printf '%s' "${intake_source}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
case "${intake_source}" in
  github-issue-label|github-vote-comment|github-issue-handoff|workflow-dispatch|github-recovery-console|railway-public-edge)
    dispatch_cmd+=(-f intake_source="${intake_source}")
    ;;
esac
execution_mode_override="$(printf '%s' "${execution_mode_override}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
case "${execution_mode_override}" in
  auto|primary|backup-safe|backup-heavy) ;;
  *) execution_mode_override="auto" ;;
esac
if [[ "${execution_mode_override}" != "auto" ]]; then
  dispatch_cmd+=(-f execution_mode_override="${execution_mode_override}")
fi

if [[ "${dry_run}" == "true" ]]; then
  printf '%q ' "${dispatch_cmd[@]}"
  printf '\n'
  exit 0
fi

"${dispatch_cmd[@]}" >/dev/null
echo "handoff_target=fugue-bridge"
echo "workflow_file=${workflow_file}"
