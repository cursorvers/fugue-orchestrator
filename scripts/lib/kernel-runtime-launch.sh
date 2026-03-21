#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
THREAD_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh"
KERNEL_BIN="${KERNEL_BIN:-$HOME/bin/kernel}"
FUGUE_BIN="${FUGUE_BIN:-$HOME/bin/fugue}"

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-launch.sh command <new|resume> <kernel|fugue> <run_id> <project> <purpose> <tmux_session> [focus...]
EOF
}

shell_join_quoted() {
  local arg out=""
  for arg in "$@"; do
    if [[ -n "${out}" ]]; then
      out+=" "
    fi
    out+="$(printf '%q' "${arg}")"
  done
  printf '%s' "${out}"
}

normalize_runtime() {
  local value="${1:-}"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  case "${value}" in
    kernel|fugue)
      printf '%s\n' "${value}"
      ;;
    *)
      echo "unsupported runtime: ${value}" >&2
      exit 2
      ;;
  esac
}

command_for() {
  local launch_mode="${1:-}"
  local runtime="${2:-}"
  local run_id="${3:-}"
  local project="${4:-}"
  local purpose="${5:-}"
  local tmux_session="${6:-}"
  shift 6 || true

  local env_args=(
    "KERNEL_RUN_ID=${run_id}"
    "KERNEL_PROJECT=${project}"
    "KERNEL_PURPOSE=${purpose}"
    "KERNEL_TMUX_SESSION=${tmux_session}"
    "KERNEL_AUTO_OPEN_LATEST=false"
    "FUGUE_ROOT=${ROOT_DIR}"
  )

  runtime="$(normalize_runtime "${runtime}")"
  case "${runtime}" in
    kernel)
      if [[ "${launch_mode}" == "resume" ]]; then
        printf 'bash %q launch %q\n' "${THREAD_SCRIPT}" "${run_id}"
        return 0
      fi
      env_args+=("KERNEL_RUNTIME=kernel")
      printf 'env %s %q' "$(shell_join_quoted "${env_args[@]}")" "${KERNEL_BIN}"
      if (($#)); then
        printf ' %s' "$(shell_join_quoted "$@")"
      fi
      printf '\n'
      ;;
    fugue)
      env_args+=("KERNEL_RUNTIME=fugue" "FUGUE_RUNTIME=fugue" "FUGUE_ORCHESTRATION_RUNTIME=fugue")
      if (($#)); then
        env_args+=("KERNEL_FUGUE_FOCUS=$(printf '%s' "$*")")
      fi
      printf 'env %s %q' "$(shell_join_quoted "${env_args[@]}")" "${FUGUE_BIN}"
      if [[ "${launch_mode}" == "resume" ]]; then
        printf ' %s' "$(shell_join_quoted "Resume FUGUE orchestration for Kernel run ${run_id}.")"
      elif (($#)); then
        printf ' %s' "$(shell_join_quoted "$@")"
      fi
      printf '\n'
      ;;
  esac
}

cmd="${1:-}"
case "${cmd}" in
  command)
    shift || true
    [[ $# -ge 6 ]] || {
      usage >&2
      exit 2
    }
    command_for "$@"
    ;;
  help|-h|--help|"")
    usage
    ;;
  *)
    echo "Unknown subcommand: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
