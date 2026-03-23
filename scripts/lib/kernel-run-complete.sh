#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE_GATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-phase-gate.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
RUNNER_SCRIPT="${ROOT_DIR}/scripts/local/run-kernel-task-completion-backup.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"

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
  kernel-run-complete.sh --summary <text> [--title <text>] [--uiux] [--no-gha] [--dry-run]
EOF
}

summary=""
title=""
uiux_flag=()
runner_flags=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary)
      summary="${2:-}"
      shift 2
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --uiux)
      uiux_flag=(--uiux)
      shift
      ;;
    --no-gha|--dry-run)
      runner_flags+=("$1")
      shift
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

[[ -n "${summary}" ]] || {
  echo "--summary is required" >&2
  exit 2
}

[[ -x "${RUNNER_SCRIPT}" || -f "${RUNNER_SCRIPT}" ]] || {
  echo "task completion backup runner missing: ${RUNNER_SCRIPT}" >&2
  exit 1
}

phase_args=(check verify)
if ((${#uiux_flag[@]})); then
  phase_args+=("${uiux_flag[@]}")
fi
bash "${PHASE_GATE_SCRIPT}" "${phase_args[@]}" >/dev/null

project="${KERNEL_PROJECT:-kernel-workspace}"
purpose="${KERNEL_PURPOSE:-unspecified}"
if [[ -z "${title}" ]]; then
  title="${project}:${purpose}"
fi

workspace_receipt_path=""
if [[ -f "${WORKSPACE_SCRIPT}" ]]; then
  workspace_receipt_path="$(KERNEL_RUN_ID="${RUN_ID}" bash "${WORKSPACE_SCRIPT}" write)"
fi

bash "${RUNNER_SCRIPT}" \
  --assistant codex \
  --source kernel-run-complete \
  --session-id "${RUN_ID}" \
  --summary "${summary}" \
  --cwd "${ROOT_DIR}" \
  --title "${title}" \
  "${runner_flags[@]+"${runner_flags[@]}"}" \
  >/dev/null

KERNEL_RUN_ID="${RUN_ID}" \
KERNEL_PHASE="verify" \
KERNEL_SUMMARY="${summary}" \
KERNEL_WORKSPACE_RECEIPT_PATH="${workspace_receipt_path}" \
  bash "${COMPACT_SCRIPT}" update run_completed "${summary}" >/dev/null

printf 'kernel run completion:\n'
printf '  - run id: %s\n' "${RUN_ID}"
printf '  - title: %s\n' "${title}"
printf '  - summary: %s\n' "${summary}"
