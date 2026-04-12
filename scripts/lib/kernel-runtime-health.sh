#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
MUTATE_LEDGER="${KERNEL_RUNTIME_HEALTH_MUTATE:-true}"

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
  kernel-runtime-health.sh status [run_id]
EOF
}

derive_lifecycle_state() {
  local state="${1:-unknown}"
  local scheduler_state="${2:-unknown}"
  if [[ "${state}" == "degraded-allowed" ]]; then
    case "${scheduler_state}" in
      running|continuity_degraded)
        printf 'live-continuity-degraded\n'
        return 0
        ;;
    esac
  fi
  case "${scheduler_state}" in
    running)
      printf 'live-running\n'
      ;;
    continuity_degraded)
      printf 'live-continuity-degraded\n'
      ;;
    terminal)
      printf 'terminal\n'
      ;;
    awaiting_human)
      printf 'awaiting-human\n'
      ;;
    retry_queued)
      printf 'retry-queued\n'
      ;;
    claimed|"")
      case "${state}" in
        healthy|degraded-allowed)
          printf 'bootstrap-valid\n'
          ;;
        *)
          printf 'blocked\n'
          ;;
      esac
      ;;
    *)
      case "${state}" in
        healthy|degraded-allowed)
          printf 'bootstrap-valid\n'
          ;;
        *)
          printf 'blocked\n'
          ;;
      esac
      ;;
  esac
}

cmd_status() {
  local run_id="${1:-${RUN_ID}}"
  local receipt_path present glm_mode lane_count has_codex has_glm specialist_count receipt_mode state reason
  local active_model_count manifest_lane_count has_agent_labels has_subagent_labels
  local ledger_file codex_success glm_success specialist_success_count scheduler_state lifecycle_state
  local exit_code=0
  receipt_path="$(KERNEL_RUN_ID="${run_id}" bash "${RECEIPT_SCRIPT}" path)"
  present=false
  if [[ -f "${receipt_path}" ]]; then
    present=true
    lane_count="$(jq -r '.lane_count // 0' "${receipt_path}")"
    has_codex="$(jq -r '.has_codex // false' "${receipt_path}")"
    has_glm="$(jq -r '.has_glm // false' "${receipt_path}")"
    specialist_count="$(jq -r '.specialist_count // 0' "${receipt_path}")"
    receipt_mode="$(jq -r '.mode // "unknown"' "${receipt_path}")"
    active_model_count="$(jq -r '.active_model_count // 0' "${receipt_path}")"
    manifest_lane_count="$(jq -r '.manifest_lane_count // 0' "${receipt_path}")"
    has_agent_labels="$(jq -r '.has_agent_labels // false' "${receipt_path}")"
    has_subagent_labels="$(jq -r '.has_subagent_labels // false' "${receipt_path}")"
  else
    lane_count=0
    has_codex=false
    has_glm=false
    specialist_count=0
    receipt_mode=unknown
    active_model_count=0
    manifest_lane_count=0
    has_agent_labels=false
    has_subagent_labels=false
  fi
  glm_mode="$(KERNEL_RUN_ID="${run_id}" bash "${GLM_STATE_SCRIPT}" status | sed -n 's/  - mode: //p' | head -n 1)"
  ledger_file="${KERNEL_RUNTIME_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" runtime-ledger-file)}"
  if [[ -f "${ledger_file}" ]]; then
    codex_success="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].provider_usage.codex.success_count // 0' "${ledger_file}")"
    glm_success="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].provider_usage.glm.success_count // 0' "${ledger_file}")"
    scheduler_state="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].scheduler_state // "unknown"' "${ledger_file}")"
    specialist_success_count="$(jq -r --arg run_id "${run_id}" '
      (.runs[$run_id].provider_usage // {})
      | to_entries
      | map(select(.key != "codex" and .key != "glm" and ((.value.success_count // 0) > 0)))
      | length
    ' "${ledger_file}")"
  else
    codex_success=0
    glm_success=0
    scheduler_state=unknown
    specialist_success_count=0
  fi

  state="healthy"
  reason="bootstrap-valid"

  if [[ "${present}" != true ]]; then
    state="invalid"
    reason="bootstrap-receipt-missing"
  elif (( lane_count < 6 )); then
    state="invalid"
    reason="lane-count-below-minimum"
  elif (( active_model_count < 3 )); then
    state="invalid"
    reason="active-model-count-below-minimum"
  elif (( manifest_lane_count < 6 )); then
    state="invalid"
    reason="manifest-lane-count-below-minimum"
  elif [[ "${has_agent_labels}" != "true" ]]; then
    state="invalid"
    reason="agent-labels-missing-from-receipt"
  elif [[ "${has_subagent_labels}" != "true" ]]; then
    state="invalid"
    reason="subagent-labels-missing-from-receipt"
  elif (( codex_success < 1 )); then
    state="invalid"
    reason="codex-provider-evidence-missing"
  elif [[ "${has_codex}" != "true" ]]; then
    state="invalid"
    reason="codex-missing-from-receipt"
  elif [[ "${receipt_mode}" == "degraded-allowed" || "${glm_mode}" == "degraded-allowed" ]]; then
    if (( specialist_count < 2 )); then
      state="invalid"
      reason="degraded-specialist-count-insufficient"
    elif (( specialist_success_count < 2 )); then
      state="invalid"
      reason="degraded-specialist-provider-evidence-insufficient"
    else
      state="degraded-allowed"
      reason="glm-degraded"
    fi
  elif [[ "${has_glm}" != "true" ]]; then
    state="invalid"
    reason="glm-missing-from-normal-receipt"
  elif (( glm_success < 1 )); then
    state="invalid"
    reason="glm-provider-evidence-missing"
  elif (( specialist_count < 1 )); then
    state="invalid"
    reason="specialist-missing-from-normal-receipt"
  elif (( specialist_success_count < 1 )); then
    state="invalid"
    reason="specialist-provider-evidence-missing"
  fi

  if [[ "${state}" == "invalid" ]]; then
    exit_code=1
  fi

  if [[ "${MUTATE_LEDGER}" == "true" ]]; then
    KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" transition "${state}" "${reason}" "${receipt_path}" >/dev/null
  fi
  lifecycle_state="$(derive_lifecycle_state "${state}" "${scheduler_state}")"

  printf 'runtime health:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - state: %s\n' "${state}"
  printf '  - reason: %s\n' "${reason}"
  printf '  - lifecycle state: %s\n' "${lifecycle_state}"
  printf '  - scheduler state: %s\n' "${scheduler_state}"
  printf '  - glm mode: %s\n' "${glm_mode}"
  printf '  - codex provider success: %s\n' "${codex_success}"
  printf '  - glm provider success: %s\n' "${glm_success}"
  printf '  - specialist provider success count: %s\n' "${specialist_success_count}"
  printf '  - receipt path: %s\n' "${receipt_path}"
  printf '  - mutating: %s\n' "${MUTATE_LEDGER}"
  return "${exit_code}"
}

cmd="${1:-status}"
case "${cmd}" in
  status)
    shift || true
    cmd_status "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
