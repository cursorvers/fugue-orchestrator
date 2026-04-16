#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
MEMORY_QUERY_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-memory-query.sh"
CODEX_BIN="${CODEX_BIN:-/opt/homebrew/bin/codex}"

usage() {
  cat <<'EOF'
Usage:
  kernel-codex-thread.sh title [run_id]
  kernel-codex-thread.sh prompt [run_id]
  kernel-codex-thread.sh launch [run_id]
EOF
}

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"

compact_path_for() {
  KERNEL_RUN_ID="${1:-${RUN_ID}}" bash "${COMPACT_SCRIPT}" path
}

compact_json() {
  local run_id="${1:-${RUN_ID}}"
  local path
  path="$(compact_path_for "${run_id}")"
  [[ -f "${path}" ]] || {
    echo "compact artifact missing for run: ${run_id}" >&2
    exit 1
  }
  jq -c '.' "${path}"
}

cmd_title() {
  local run_id="${1:-${RUN_ID}}"
  compact_json "${run_id}" | jq -r '.codex_thread_title // (.project + ":" + .purpose)'
}

cmd_prompt() {
  local run_id="${1:-${RUN_ID}}"
  local json title summary next_action phase mode runtime handoff_packet
  json="$(compact_json "${run_id}")"
  title="$(jq -r '.codex_thread_title // (.project + ":" + .purpose)' <<<"${json}")"
  summary="$(jq -r '(.summary // []) | join(" || ")' <<<"${json}")"
  next_action="$(jq -r '(.next_action // [])[0] // ""' <<<"${json}")"
  phase="$(jq -r '.current_phase // "unknown"' <<<"${json}")"
  mode="$(jq -r '.mode // "unknown"' <<<"${json}")"
  runtime="$(jq -r '.runtime // "kernel"' <<<"${json}")"
  handoff_packet=""
  if [[ -f "${MEMORY_QUERY_SCRIPT}" ]]; then
    handoff_packet="$(bash "${MEMORY_QUERY_SCRIPT}" packet --run "${run_id}" --format text 2>/dev/null || true)"
  fi
  cat <<EOF
Kernel thread: ${title}
Continue Kernel run ${run_id}.
Phase: ${phase}
Mode: ${mode}
Runtime: ${runtime}
Next action: ${next_action}
Summary: ${summary}
${handoff_packet}
Resume this run as its dedicated Codex thread and continue under the repository Kernel contract.
EOF
}

cmd_launch() {
  local run_id="${1:-${RUN_ID}}"
  local prompt
  prompt="$(cmd_prompt "${run_id}")"
  if [[ "${KERNEL_CODEX_THREAD_PRINT_ONLY:-false}" == "true" ]]; then
    printf '%s\n' "${prompt}"
    return 0
  fi
  exec "${CODEX_BIN}" -C "${ROOT_DIR}" "${prompt}"
}

cmd="${1:-title}"
case "${cmd}" in
  title)
    shift || true
    cmd_title "$@"
    ;;
  prompt)
    shift || true
    cmd_prompt "$@"
    ;;
  launch)
    shift || true
    cmd_launch "$@"
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
