#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/kernel-4pane-launch.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_4PANE_NO_ATTACH=true
export CODEX_BIN="/usr/bin/printf"
export TMUX_ACTION_LOG="${TMP_DIR}/tmux-actions.log"
export TMUX_STATE_FILE="${TMP_DIR}/tmux-sessions.txt"
mkdir -p "${KERNEL_COMPACT_DIR}"
: > "${TMUX_ACTION_LOG}"
: > "${TMUX_STATE_FILE}"

TMUX_STUB="${TMP_DIR}/tmux-stub.sh"
cat > "${TMUX_STUB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

action_log="${TMUX_ACTION_LOG:?}"
state_file="${TMUX_STATE_FILE:?}"
counter_file="${state_file}.counter"
touch "${counter_file}"
count="$(cat "${counter_file}" 2>/dev/null || printf '0')"

next_pane() {
  count=$((count + 1))
  printf '%s' "${count}" > "${counter_file}"
  printf '%%%s\n' "${count}"
}

session_exists() {
  local target="${1:-}"
  grep -Fxq "${target}" "${state_file}" 2>/dev/null
}

case "${1:-}" in
  has-session)
    target="${3:-}"
    target="${target#=}"
    session_exists "${target}"
    ;;
  new-session)
    printf 'new-session %s\n' "$*" >> "${action_log}"
    session=""
    while [[ $# -gt 0 ]]; do
      if [[ "${1:-}" == "-s" ]]; then
        session="${2:-}"
        break
      fi
      shift
    done
    if [[ -n "${session}" ]]; then
      printf '%s\n' "${session}" >> "${state_file}"
    fi
    ;;
  display-message)
    printf '%%0\n'
    ;;
  split-window)
    printf 'split-window %s\n' "$*" >> "${action_log}"
    next_pane
    ;;
  select-layout|resize-pane|set-option|send-keys|attach)
    printf '%s %s\n' "${1}" "$*" >> "${action_log}"
    ;;
  show-options)
    target="${3:-}"
    target="${target#=}"
    option_name="${5:-}"
    if [[ "${option_name}" == "@kernel_run_id" ]]; then
      value_file="${state_file}.${target}.run_id"
      if [[ -f "${value_file}" ]]; then
        cat "${value_file}"
      fi
      exit 0
    fi
    ;;
  *)
    ;;
esac
EOF
chmod +x "${TMUX_STUB}"
export TMUX_BIN="${TMUX_STUB}"

out="$(bash "${SCRIPT}" --purpose smoke)"
grep -Fq 'Kernel ready: fugue-orchestrator-public__smoke [' <<<"${out}"
grep -Fq 'send-keys send-keys -t %0' "${TMUX_ACTION_LOG}"
grep -Fq '/usr/bin/printf -C /Users/masayuki/Dev/fugue-orchestrator-public' "${TMUX_ACTION_LOG}"
if grep -Fq 'kernel-codex-thread.sh' "${TMUX_ACTION_LOG}"; then
  echo "left pane should start raw codex, not inject the kernel thread prompt" >&2
  exit 1
fi

: > "${TMUX_ACTION_LOG}"
printf '%s\n' 'fugue-orchestrator-public__resume' > "${TMUX_STATE_FILE}"
cat > "${KERNEL_COMPACT_DIR}/run-resume.json" <<'EOF'
{"run_id":"run-resume","project":"fugue-orchestrator-public","purpose":"resume","tmux_session":"fugue-orchestrator-public__resume","updated_at":"2026-03-31T10:00:00Z"}
EOF

out="$(bash "${SCRIPT}" --run run-resume)"
grep -Fq 'Kernel ready: fugue-orchestrator-public__resume [run-resume]' <<<"${out}"
if grep -Fq 'new-session' "${TMUX_ACTION_LOG}"; then
  echo "resume should reuse the existing tmux session" >&2
  exit 1
fi
if grep -Fq 'send-keys' "${TMUX_ACTION_LOG}"; then
  echo "resume should not relaunch pane commands when the tmux session already exists" >&2
  exit 1
fi

: > "${TMUX_ACTION_LOG}"
printf '%s\n' 'fugue-orchestrator-public__conflict' > "${TMUX_STATE_FILE}"
printf '%s\n' 'run-other' > "${TMUX_STATE_FILE}.fugue-orchestrator-public__conflict.run_id"
cat > "${KERNEL_COMPACT_DIR}/run-conflict.json" <<'EOF'
{"run_id":"run-conflict","project":"fugue-orchestrator-public","purpose":"conflict","tmux_session":"fugue-orchestrator-public__conflict","updated_at":"2026-03-31T10:00:00Z"}
EOF

if bash "${SCRIPT}" --run run-conflict >/dev/null 2>&1; then
  echo "resume should fail fast when the existing tmux session belongs to another run" >&2
  exit 1
fi

echo "kernel 4pane launch check passed"
