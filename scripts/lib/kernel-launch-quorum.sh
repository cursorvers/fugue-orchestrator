#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
GLM_EXEC_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-exec.sh"
OPTIONAL_EXEC_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-exec.sh"
THREAD_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh"

usage() {
  cat <<'EOF'
Usage:
  kernel-launch-quorum.sh run <mode> <providers_csv> <purpose> [focus...]
EOF
}

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

canonical_provider() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    codex) printf 'codex\n' ;;
    glm) printf 'glm\n' ;;
    gemini|gemini-cli) printf 'gemini-cli\n' ;;
    cursor|cursor-cli) printf 'cursor-cli\n' ;;
    copilot|copilot-cli) printf 'copilot-cli\n' ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

trim() {
  printf '%s' "${1:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

build_prompt() {
  local mode="${1:?mode required}"
  local providers_csv="${2:?providers required}"
  local purpose="${3:?purpose required}"
  shift 3 || true
  local focus_text
  focus_text="$(printf '%s ' "$@" | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//')"
  cat <<EOF
Kernel launch quorum preflight for run $(default_run_id).
Purpose: ${purpose}
Mode: ${mode}
Providers: ${providers_csv}
Focus: ${focus_text:-general implementation}
Return a short execution-oriented critique that helps the Codex implementation lane start correctly.
EOF
}

run_glm_lane() {
  local prompt="${1:?prompt required}"
  bash "${GLM_EXEC_SCRIPT}" -p "${prompt}" >/dev/null
}

run_specialist_lane() {
  local provider="${1:?provider required}"
  local prompt="${2:?prompt required}"
  bash "${OPTIONAL_EXEC_SCRIPT}" "${provider}" -p "${prompt}" >/dev/null
}

run_codex_prompt_check() {
  local run_id="${1:?run_id required}"
  local prompt
  prompt="$(env KERNEL_RUN_ID="${run_id}" bash "${THREAD_SCRIPT}" prompt "${run_id}")"
  [[ -n "${prompt}" ]]
}

cmd_run() {
  local mode="${1:-}"
  local providers_csv="${2:-}"
  local purpose="${3:-launch}"
  shift 3 || true
  [[ -n "${mode}" && -n "${providers_csv}" ]] || {
    usage >&2
    exit 2
  }

  local run_id prompt provider specialist_count=0
  run_id="$(default_run_id)"
  prompt="$(build_prompt "${mode}" "${providers_csv}" "${purpose}" "$@")"

  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-event kernel-launch-quorum start "mode=${mode}; providers=${providers_csv}" >/dev/null

  run_codex_prompt_check "${run_id}"

  if [[ "${mode}" != "degraded-allowed" ]]; then
    run_glm_lane "${prompt}"
  fi

  while IFS= read -r provider; do
    provider="$(canonical_provider "$(trim "${provider}")")"
    [[ -n "${provider}" ]] || continue
    case "${provider}" in
      codex|glm) continue ;;
    esac
    run_specialist_lane "${provider}" "${prompt}"
    specialist_count=$((specialist_count + 1))
  done < <(printf '%s\n' "${providers_csv}" | tr ',' '\n')

  if [[ "${mode}" == "degraded-allowed" ]]; then
    (( specialist_count >= 2 )) || {
      echo "launch quorum requires two specialists in degraded mode" >&2
      exit 1
    }
  else
    (( specialist_count >= 1 )) || {
      echo "launch quorum requires one specialist in normal mode" >&2
      exit 1
    }
  fi

  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-event kernel-launch-quorum finish "mode=${mode}; specialists=${specialist_count}" >/dev/null
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  run)
    cmd_run "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
