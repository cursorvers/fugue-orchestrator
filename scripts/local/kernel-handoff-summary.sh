#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
COMPACT_DIR="${KERNEL_COMPACT_DIR:-$(bash "${ROOT_DIR}/scripts/lib/kernel-state-paths.sh" compact-dir)}"

RUN_ID=""
COMPACT_PATH=""

usage() {
  cat <<'EOF'
Usage:
  scripts/local/kernel-handoff-summary.sh [--run-id <id>] [--compact-path <path>]

Options:
  --run-id <id>         Specific Kernel run id to summarize
  --compact-path <path> Specific compact artifact path
  -h, --help            Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --compact-path)
      COMPACT_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

latest_compact_path() {
  ls -t "${COMPACT_DIR}"/*.json 2>/dev/null | head -n 1 || true
}

compact_path_for_run() {
  local run_id="${1:?run id is required}"
  KERNEL_RUN_ID="${run_id}" bash "${COMPACT_SCRIPT}" path
}

phase_artifact_focus_key() {
  case "${1:-}" in
    plan)
      printf 'plan_report_path\n'
      ;;
    critique)
      printf 'critic_report_path\n'
      ;;
    implement|implementation)
      printf 'implementation_report_path\n'
      ;;
    verify|verification)
      printf 'verification_report_path\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

if [[ -z "${COMPACT_PATH}" ]]; then
  if [[ -n "${RUN_ID}" ]]; then
    COMPACT_PATH="$(compact_path_for_run "${RUN_ID}")"
  else
    COMPACT_PATH="$(latest_compact_path)"
  fi
fi

if [[ -z "${COMPACT_PATH}" || ! -f "${COMPACT_PATH}" ]]; then
  echo "No Kernel compact artifact found." >&2
  exit 1
fi

compact_json="$(jq -c '.' "${COMPACT_PATH}")"
RUN_ID="${RUN_ID:-$(jq -r '.run_id // ""' <<<"${compact_json}")}"
[[ -n "${RUN_ID}" ]] || {
  echo "run_id missing in compact artifact: ${COMPACT_PATH}" >&2
  exit 1
}

workspace_receipt_path="$(jq -r '.workspace_receipt_path // empty' <<<"${compact_json}")"
if [[ -z "${workspace_receipt_path}" && -f "${WORKSPACE_SCRIPT}" ]]; then
  workspace_receipt_path="$(KERNEL_RUN_ID="${RUN_ID}" bash "${WORKSPACE_SCRIPT}" receipt-path 2>/dev/null || true)"
fi
if [[ -n "${workspace_receipt_path}" && ! -f "${workspace_receipt_path}" ]]; then
  workspace_receipt_path=""
fi

workspace_json=""
runtime_ledger_path=""
bootstrap_receipt_path=""
consensus_receipt_path=""
workspace_dir=""
artifacts_dir=""
logs_dir=""
traces_dir=""
if [[ -n "${workspace_receipt_path}" ]]; then
  workspace_json="$(jq -c '.' "${workspace_receipt_path}")"
  runtime_ledger_path="$(jq -r '.runtime_ledger_path // ""' <<<"${workspace_json}")"
  bootstrap_receipt_path="$(jq -r '.bootstrap_receipt_path // ""' <<<"${workspace_json}")"
  consensus_receipt_path="$(jq -r '.consensus_receipt_path // ""' <<<"${workspace_json}")"
  workspace_dir="$(jq -r '.workspace_dir // ""' <<<"${workspace_json}")"
  artifacts_dir="$(jq -r '.artifacts_dir // ""' <<<"${workspace_json}")"
  logs_dir="$(jq -r '.logs_dir // ""' <<<"${workspace_json}")"
  traces_dir="$(jq -r '.traces_dir // ""' <<<"${workspace_json}")"
fi

current_phase="$(jq -r '.current_phase // "unknown"' <<<"${compact_json}")"
focus_key="$(phase_artifact_focus_key "${current_phase}")"
phase_artifact_focus="none"
if [[ -n "${focus_key}" ]]; then
  phase_artifact_focus="$(jq -r --arg key "${focus_key}" '.phase_artifacts[$key] // "none"' <<<"${compact_json}")"
fi

summary="$(jq -r '(.summary // []) | join(" || ")' <<<"${compact_json}")"
next_action="$(jq -r '(.next_action // [])[0] // "none"' <<<"${compact_json}")"
active_models="$(jq -r '(.active_models // []) | join(",")' <<<"${compact_json}")"
decisions="$(jq -r '(.decisions // []) | join(" | ")' <<<"${compact_json}")"

printf 'kernel handoff summary:\n'
printf '  - run id: %s\n' "${RUN_ID}"
printf '  - compact path: %s\n' "${COMPACT_PATH}"
printf '  - project: %s\n' "$(jq -r '.project // "kernel-workspace"' <<<"${compact_json}")"
printf '  - purpose: %s\n' "$(jq -r '.purpose // "unspecified"' <<<"${compact_json}")"
printf '  - runtime: %s\n' "$(jq -r '.runtime // "kernel"' <<<"${compact_json}")"
printf '  - phase: %s\n' "${current_phase}"
printf '  - mode: %s\n' "$(jq -r '.mode // "unknown"' <<<"${compact_json}")"
printf '  - tmux session: %s\n' "$(jq -r '.tmux_session // ""' <<<"${compact_json}")"
printf '  - codex thread: %s\n' "$(jq -r '.codex_thread_title // ""' <<<"${compact_json}")"
printf '  - active models: %s\n' "${active_models:-none}"
printf '  - scheduler state: %s\n' "$(jq -r '.scheduler_state // "unknown"' <<<"${compact_json}")"
printf '  - scheduler reason: %s\n' "$(jq -r '.scheduler_reason // ""' <<<"${compact_json}")"
printf '  - next action: %s\n' "${next_action}"
printf '  - phase artifact focus: %s=%s\n' "${focus_key:-none}" "${phase_artifact_focus}"
printf '  - decisions: %s\n' "${decisions:-none}"
printf '  - summary: %s\n' "${summary:-none}"
printf '  - updated at: %s\n' "$(jq -r '.updated_at // ""' <<<"${compact_json}")"
printf '  - workspace receipt path: %s\n' "${workspace_receipt_path}"
printf '  - workspace dir: %s\n' "${workspace_dir}"
printf '  - artifacts dir: %s\n' "${artifacts_dir}"
printf '  - logs dir: %s\n' "${logs_dir}"
printf '  - traces dir: %s\n' "${traces_dir}"
printf '  - bootstrap receipt path: %s\n' "${bootstrap_receipt_path}"
printf '  - runtime ledger path: %s\n' "${runtime_ledger_path}"
printf '  - consensus receipt path: %s\n' "${consensus_receipt_path}"
printf '  - recover command: codex-kernel-guard recover-run %s\n' "${RUN_ID}"
printf '  - codex prompt command: bash %s prompt %s\n' "${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh" "${RUN_ID}"
