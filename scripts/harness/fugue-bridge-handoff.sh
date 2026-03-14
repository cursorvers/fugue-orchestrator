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
implement_request=""
implement_confirmed=""
vote_command="false"
intake_source=""
kernel_handoff_mode="false"
content_hint_applied="false"
content_action_hint=""
content_skill_hint=""
content_reason=""
cost_provider_priority=""
cost_copilot_policy=""
cost_metered_policy=""
metered_reason="none"
fallback_used="false"
missing_lane="none"
fallback_provider="none"
fallback_reason=""
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
  --implement-request <bool>       Resolved implementation intent snapshot
  --implement-confirmed <bool>     Resolved implementation confirmation snapshot
  --vote-command <bool>            True when the handoff originated from `/vote`
  --intake-source <value>          Intake source marker for audit/policy
  --kernel-handoff-mode <bool>     Kernel continuation handoff mode
  --content-hint-applied <bool>    Content hint snapshot flag
  --content-action-hint <value>    Content action snapshot
  --content-skill-hint <value>     Content skill snapshot
  --content-reason <value>         Content reason snapshot
  --cost-provider-priority <csv>   Cost policy provider priority snapshot
  --cost-copilot-policy <value>    Copilot policy snapshot
  --cost-metered-policy <value>    Metered policy snapshot
  --metered-reason <value>         Metered reason snapshot
  --fallback-used <bool>           Fallback-used snapshot
  --missing-lane <value>           Missing-lane snapshot
  --fallback-provider <value>      Fallback-provider snapshot
  --fallback-reason <value>        Fallback-reason snapshot
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
    --kernel-handoff-mode)
      kernel_handoff_mode="${2:-false}"
      shift 2
      ;;
    --content-hint-applied)
      content_hint_applied="${2:-false}"
      shift 2
      ;;
    --content-action-hint)
      content_action_hint="${2:-}"
      shift 2
      ;;
    --content-skill-hint)
      content_skill_hint="${2:-}"
      shift 2
      ;;
    --content-reason)
      content_reason="${2:-}"
      shift 2
      ;;
    --cost-provider-priority)
      cost_provider_priority="${2:-}"
      shift 2
      ;;
    --cost-copilot-policy)
      cost_copilot_policy="${2:-}"
      shift 2
      ;;
    --cost-metered-policy)
      cost_metered_policy="${2:-}"
      shift 2
      ;;
    --metered-reason)
      metered_reason="${2:-none}"
      shift 2
      ;;
    --fallback-used)
      fallback_used="${2:-false}"
      shift 2
      ;;
    --missing-lane)
      missing_lane="${2:-none}"
      shift 2
      ;;
    --fallback-provider)
      fallback_provider="${2:-none}"
      shift 2
      ;;
    --fallback-reason)
      fallback_reason="${2:-}"
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
kernel_handoff_mode="$(printf '%s' "${kernel_handoff_mode}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${kernel_handoff_mode}" == "true" ]]; then
  dispatch_cmd+=(-f kernel_handoff_mode="true")
fi
content_hint_applied="$(printf '%s' "${content_hint_applied}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${content_hint_applied}" == "true" ]]; then
  dispatch_cmd+=(-f content_hint_applied="true")
fi
content_action_hint="$(printf '%s' "${content_action_hint}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${content_action_hint}" ]]; then
  dispatch_cmd+=(-f content_action_hint="${content_action_hint}")
fi
content_skill_hint="$(printf '%s' "${content_skill_hint}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${content_skill_hint}" ]]; then
  dispatch_cmd+=(-f content_skill_hint="${content_skill_hint}")
fi
content_reason="$(printf '%s' "${content_reason}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${content_reason}" ]]; then
  dispatch_cmd+=(-f content_reason="${content_reason}")
fi
cost_provider_priority="$(printf '%s' "${cost_provider_priority}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
if [[ -n "${cost_provider_priority}" ]]; then
  dispatch_cmd+=(-f cost_provider_priority="${cost_provider_priority}")
fi
cost_copilot_policy="$(printf '%s' "${cost_copilot_policy}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${cost_copilot_policy}" ]]; then
  dispatch_cmd+=(-f cost_copilot_policy="${cost_copilot_policy}")
fi
cost_metered_policy="$(printf '%s' "${cost_metered_policy}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${cost_metered_policy}" ]]; then
  dispatch_cmd+=(-f cost_metered_policy="${cost_metered_policy}")
fi
metered_reason="$(printf '%s' "${metered_reason}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${metered_reason}" ]]; then
  dispatch_cmd+=(-f metered_reason="${metered_reason}")
fi
missing_lane="$(printf '%s' "${missing_lane}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${missing_lane}" ]]; then
  dispatch_cmd+=(-f missing_lane="${missing_lane}")
fi
intake_source="$(printf '%s' "${intake_source}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
case "${intake_source}" in
  github-issue-label|github-vote-comment|github-issue-handoff|workflow-dispatch|github-recovery-console|railway-public-edge)
    dispatch_cmd+=(-f intake_source="${intake_source}")
    ;;
esac

if [[ "${dry_run}" == "true" ]]; then
  printf '%q ' "${dispatch_cmd[@]}"
  printf '\n'
  exit 0
fi

"${dispatch_cmd[@]}" >/dev/null
echo "handoff_target=fugue-bridge"
echo "workflow_file=${workflow_file}"
