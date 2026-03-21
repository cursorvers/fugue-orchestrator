#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"

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

ledger_file() {
  printf '%s\n' "${KERNEL_RUNTIME_LEDGER_FILE:-$HOME/.config/kernel/runtime-ledger.json}"
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
  check_phase >/dev/null
  KERNEL_RUN_ID="${RUN_ID}" KERNEL_PHASE="${PHASE}" bash "${COMPACT_SCRIPT}" update phase_completed "phase=${PHASE} completed" >/dev/null
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
