#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
MILESTONE_RECORD_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-milestone-record.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
CONSENSUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-consensus-evidence.sh"

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"

usage() {
  cat <<'EOF'
Usage:
  kernel-phase-gate.sh check <requirements|plan|critique|simulate|implement|verify> [--uiux]
  kernel-phase-gate.sh complete <requirements|plan|critique|simulate|implement|verify> [--uiux]
EOF
}

normalize_phase() {
  case "${1:-}" in
    requirements|requirement|requirements-definition) printf 'requirements\n' ;;
    plan|planning) printf 'plan\n' ;;
    critique|critical-review) printf 'critique\n' ;;
    simulate|simulation) printf 'simulate\n' ;;
    implement|implementation) printf 'implement\n' ;;
    verify|verification) printf 'verify\n' ;;
    *)
      printf 'unknown\n'
      return 1
      ;;
  esac
}

receipt_path() {
  KERNEL_RUN_ID="${RUN_ID}" bash "${RECEIPT_SCRIPT}" path
}

receipt_json() {
  local path
  path="$(receipt_path)"
  [[ -f "${path}" ]] || return 1
  jq -c '.' "${path}"
}

compact_json() {
  local path
  path="$(KERNEL_RUN_ID="${RUN_ID}" bash "${COMPACT_SCRIPT}" path "${RUN_ID}" 2>/dev/null || true)"
  [[ -n "${path}" && -f "${path}" ]] || return 1
  jq -c '.' "${path}"
}

consensus_json() {
  local path
  path="$(KERNEL_RUN_ID="${RUN_ID}" bash "${CONSENSUS_SCRIPT}" path 2>/dev/null || true)"
  [[ -n "${path}" && -f "${path}" ]] || return 1
  jq -c '.' "${path}"
}

task_size_tier() {
  if [[ -n "${KERNEL_TASK_SIZE_TIER:-}" ]]; then
    printf '%s\n' "${KERNEL_TASK_SIZE_TIER}" | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  if consensus_json >/dev/null 2>&1; then
    jq -r '.task_size_tier // "medium"' <<<"$(consensus_json)"
    return 0
  fi
  printf 'medium\n'
}

local_consensus_required() {
  [[ "$(task_size_tier)" != "critical" ]]
}

check_local_consensus() {
  local json
  local_consensus_required || return 0
  json="$(consensus_json)" || fail_gate "local-consensus-evidence-missing"
  [[ "$(jq -r '.decision // "unknown"' <<<"${json}")" == "approved" ]] || fail_gate "local-consensus-not-approved"
  [[ "$(jq -r '.ok_to_execute // false' <<<"${json}")" == "true" ]] || fail_gate "local-consensus-not-executable"
}

ledger_file() {
  printf '%s\n' "${KERNEL_RUNTIME_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" runtime-ledger-file)}"
}

provider_success_count() {
  local provider="${1:-}"
  local file
  file="$(ledger_file)"
  [[ -f "${file}" ]] || {
    printf '0\n'
    return 0
  }
  jq -r --arg run_id "${RUN_ID}" --arg provider "${provider}" '.runs[$run_id].provider_usage[$provider].success_count // 0' "${file}"
}

specialist_success_count() {
  local file
  file="$(ledger_file)"
  [[ -f "${file}" ]] || {
    printf '0\n'
    return 0
  }
  jq -r --arg run_id "${RUN_ID}" '
    (.runs[$run_id].provider_usage // {})
    | to_entries
    | map(select(.key != "codex" and .key != "glm" and ((.value.success_count // 0) > 0)))
    | length
  ' "${file}"
}

provider_success() {
  local provider="${1:-}"
  [[ "$(provider_success_count "${provider}")" -ge 1 ]]
}

receipt_has_provider() {
  local provider="${1:-}"
  local json
  json="$(receipt_json)" || return 1
  jq -e --arg provider "${provider}" '.providers | index($provider) != null' <<<"${json}" >/dev/null
}

receipt_field_true() {
  local field="${1:-}"
  local json
  json="$(receipt_json)" || return 1
  [[ "$(jq -r --arg field "${field}" '.[$field] // false' <<<"${json}")" == "true" ]]
}

receipt_active_models_include() {
  local model="${1:-}"
  local json
  json="$(receipt_json)" || return 1
  jq -e --arg model "${model}" '.active_models | index($model) != null' <<<"${json}" >/dev/null
}

phase_artifact_env_path() {
  case "${1:-}" in
    plan_report_path)
      printf '%s\n' "${KERNEL_PLAN_REPORT_PATH:-${PLAN_REPORT_PATH:-}}"
      ;;
    critic_report_path)
      printf '%s\n' "${KERNEL_CRITIC_REPORT_PATH:-${CRITIC_REPORT_PATH:-}}"
      ;;
    implementation_report_path)
      printf '%s\n' "${KERNEL_IMPLEMENTATION_REPORT_PATH:-${IMPLEMENTATION_REPORT_PATH:-}}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

compact_phase_artifact_path() {
  local key="${1:-}"
  local json
  json="$(compact_json)" || return 1
  jq -r --arg key "${key}" '.phase_artifacts[$key] // ""' <<<"${json}"
}

required_completion_artifact_key() {
  case "${PHASE}" in
    plan)
      printf 'plan_report_path\n'
      ;;
    critique)
      printf 'critic_report_path\n'
      ;;
    implement)
      printf 'implementation_report_path\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

check_completion_artifact() {
  local key path
  key="$(required_completion_artifact_key)"
  [[ -n "${key}" ]] || return 0
  path="$(phase_artifact_env_path "${key}")"
  if [[ -z "${path}" ]]; then
    path="$(compact_phase_artifact_path "${key}" 2>/dev/null || true)"
  fi
  [[ -n "${path}" ]] || fail_gate "phase-artifact-missing:${key}"
  [[ -f "${path}" ]] || fail_gate "phase-artifact-path-missing:${key}"
  check_grounding_sections "${path}"
}

check_grounding_sections() {
  local path="${1:-}"
  local heading
  [[ "${PHASE}" == "implement" ]] || return 0
  for heading in \
    "### Evidence Quotes" \
    "### Quote-Bounded Analysis" \
    "### Unsupported Claims Removed"; do
    grep -Fxq "${heading}" "${path}" || fail_gate "phase-artifact-grounding-section-missing:${heading#\#\#\# }"
  done
}

glm_mode() {
  KERNEL_RUN_ID="${RUN_ID}" bash "${GLM_STATE_SCRIPT}" status | sed -n 's/  - mode: //p' | head -n 1
}

degraded_allowed() {
  local json receipt_mode current_glm_mode
  json="$(receipt_json)" || return 1
  receipt_mode="$(jq -r '.mode // "unknown"' <<<"${json}")"
  current_glm_mode="$(glm_mode)"
  [[ "${receipt_mode}" == "degraded-allowed" || "${current_glm_mode}" == "degraded-allowed" ]]
}

fail_gate() {
  local reason="${1:-phase-gate-failed}"
  printf 'kernel phase gate:\n'
  printf '  - run id: %s\n' "${RUN_ID}"
  printf '  - phase: %s\n' "${PHASE}"
  printf '  - passed: false\n'
  printf '  - reason: %s\n' "${reason}"
  return 1
}

pass_gate() {
  printf 'kernel phase gate:\n'
  printf '  - run id: %s\n' "${RUN_ID}"
  printf '  - phase: %s\n' "${PHASE}"
  printf '  - passed: true\n'
}

check_common_runtime() {
  receipt_json >/dev/null 2>&1 || fail_gate "bootstrap-receipt-missing"
  provider_success codex || fail_gate "codex-provider-evidence-missing"
}

check_phase() {
  check_local_consensus || return 1
  case "${PHASE}" in
    requirements|plan|critique)
      check_common_runtime || return 1
      if degraded_allowed; then
        [[ "$(specialist_success_count)" -ge 2 ]] || fail_gate "degraded-specialist-provider-evidence-insufficient"
      else
        receipt_has_provider glm || fail_gate "glm-missing-from-normal-receipt"
        provider_success glm || fail_gate "glm-provider-evidence-missing"
        [[ "$(specialist_success_count)" -ge 1 ]] || fail_gate "specialist-provider-evidence-missing"
      fi
      ;;
    simulate)
      check_common_runtime || return 1
      receipt_active_models_include "gpt-5.3-codex-spark" || fail_gate "codex-spark-evidence-missing"
      ;;
    implement|verify)
      check_common_runtime || return 1
      receipt_field_true has_subagent_labels || fail_gate "codex-subagent-evidence-missing"
      if degraded_allowed; then
        [[ "$(specialist_success_count)" -ge 2 ]] || fail_gate "degraded-specialist-provider-evidence-insufficient"
      else
        provider_success glm || fail_gate "glm-provider-evidence-missing"
      fi
      if [[ "${UIUX_REQUIRED}" == "true" ]]; then
        provider_success gemini-cli || fail_gate "gemini-uiux-evidence-missing"
      fi
      ;;
    *)
      fail_gate "unknown-phase"
      ;;
  esac

  pass_gate
}

complete_phase() {
  local workspace_receipt_path=""
  check_phase >/dev/null
  check_completion_artifact >/dev/null
  if [[ -f "${WORKSPACE_SCRIPT}" ]]; then
    workspace_receipt_path="$(KERNEL_RUN_ID="${RUN_ID}" bash "${WORKSPACE_SCRIPT}" write)"
  fi
  KERNEL_RUN_ID="${RUN_ID}" \
  KERNEL_PHASE="${PHASE}" \
  KERNEL_WORKSPACE_RECEIPT_PATH="${workspace_receipt_path}" \
    bash "${COMPACT_SCRIPT}" update phase_completed "phase=${PHASE} completed" >/dev/null
  if [[ -f "${MILESTONE_RECORD_SCRIPT}" ]]; then
    KERNEL_RUN_ID="${RUN_ID}" KERNEL_PHASE="${PHASE}" bash "${MILESTONE_RECORD_SCRIPT}" phase "${PHASE}" "phase=${PHASE} completed"
  fi
  pass_gate
}

SUBCOMMAND="${1:-check}"
shift || true
PHASE="$(normalize_phase "${1:-}")" || {
  usage >&2
  exit 2
}
shift || true

UIUX_REQUIRED=false
while (($#)); do
  case "$1" in
    --uiux)
      UIUX_REQUIRED=true
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift || true
done

case "${SUBCOMMAND}" in
  check)
    check_phase
    ;;
  complete)
    complete_phase
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: ${SUBCOMMAND}" >&2
    usage >&2
    exit 2
    ;;
esac
