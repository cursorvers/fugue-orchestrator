#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
SESSION_NAME="fugue-orchestrator__tmux-handoff"
trap 'tmux kill-session -t "${SESSION_NAME}" >/dev/null 2>&1 || true; rm -rf "${TMP_DIR}"' EXIT

export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/optional-ledger.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUN_ID="run-dr"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="tmux-handoff"
export KERNEL_PHASE="implement"
export KERNEL_OWNER="codex"
export KERNEL_RUNTIME="kernel"
export KERNEL_TMUX_SESSION="${SESSION_NAME}"
export KERNEL_BLOCKING_REASON=""
export KERNEL_NEXT_ACTIONS="resume-implementation"
export KERNEL_DECISIONS="freeze requirements|use compact handoff"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
export GEMINI_BIN=printf
export CODEX_BIN=printf
export CLAUDE_BIN=printf
export CURSOR_BIN=false
export COPILOT_BIN=false
export KERNEL_RECOVERY_LAUNCH_CODEX_THREAD=true

FAKE_BIN="${TMP_DIR}/fake-bin"
FAKE_TMUX_STATE="${TMP_DIR}/fake-tmux"
FAKE_TMUX_LOG="${TMP_DIR}/fake-tmux.log"
mkdir -p "${FAKE_BIN}" "${FAKE_TMUX_STATE}" "${KERNEL_COMPACT_DIR}"
export PATH="${FAKE_BIN}:$PATH"
export FAKE_TMUX_STATE
export FAKE_TMUX_LOG

cat >"${FAKE_BIN}/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_ROOT="${FAKE_TMUX_STATE:?}"
mkdir -p "${STATE_ROOT}"

strip_target() {
  local target="${1:-}"
  target="${target#=}"
  printf '%s\n' "${target}"
}

session_dir() {
  printf '%s/%s\n' "${STATE_ROOT}" "$1"
}

cmd="${1:-}"
shift || true
case "${cmd}" in
  has-session)
    [[ "${1:-}" == "-t" ]] || exit 2
    session="$(strip_target "${2:-}")"
    [[ -d "$(session_dir "${session}")" ]]
    ;;
  new-session)
    session=""
    window="main"
    while (($#)); do
      case "$1" in
        -d) ;;
        -s) shift; session="${1:-}" ;;
        -n) shift; window="${1:-}" ;;
      esac
      shift || true
    done
    [[ -n "${session}" ]] || exit 2
    dir="$(session_dir "${session}")"
    mkdir -p "${dir}"
    printf '%s\n' "${window}" >"${dir}/windows"
    ;;
  new-window)
    [[ "${1:-}" == "-t" ]] || exit 2
    session="$(strip_target "${2:-}")"
    shift 2 || true
    [[ "${1:-}" == "-n" ]] || exit 2
    window="${2:-}"
    dir="$(session_dir "${session}")"
    [[ -d "${dir}" ]] || exit 1
    printf '%s\n' "${window}" >>"${dir}/windows"
    ;;
  send-keys)
    [[ "${1:-}" == "-t" ]] || exit 2
    session="$(strip_target "${2:-}")"
    shift 2 || true
    printf '%s | %s\n' "${session}" "$*" >>"${FAKE_TMUX_LOG}"
    ;;
  list-windows)
    [[ "${1:-}" == "-t" ]] || exit 2
    session="$(strip_target "${2:-}")"
    dir="$(session_dir "${session}")"
    [[ -f "${dir}/windows" ]] || exit 1
    cat "${dir}/windows"
    ;;
  kill-session)
    [[ "${1:-}" == "-t" ]] || exit 2
    session="$(strip_target "${2:-}")"
    rm -rf "$(session_dir "${session}")"
    ;;
  display-message)
    if [[ "${1:-}" == "-p" && "${2:-}" == "#S" && -n "${FAKE_TMUX_SESSION:-}" ]]; then
      printf '%s\n' "${FAKE_TMUX_SESSION}"
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "${FAKE_BIN}/tmux"

SHARED_ENV_FILE="${TMP_DIR}/shared.env"
cat >"${SHARED_ENV_FILE}" <<'EOF'
OPENAI_API_KEY=sk-openai
ANTHROPIC_API_KEY=sk-anthropic
ZAI_API_KEY=sk-zai
GEMINI_API_KEY=sk-gemini
XAI_API_KEY=sk-xai
TARGET_REPO_PAT=ghp-target
FUGUE_OPS_PAT=ghp-ops
EOF
export SHARED_SECRETS_ENV_FILE="${SHARED_ENV_FILE}"
unset OPENAI_API_KEY ANTHROPIC_API_KEY ZAI_API_KEY GEMINI_API_KEY XAI_API_KEY TARGET_REPO_PAT FUGUE_OPS_PAT

bash "${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider codex success launch >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider glm success implement >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider gemini-cli success specialist >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" transition healthy "ready-for-mbp-continuation" >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh" update status_changed "Ready for MBP degraded continuation" >/dev/null

tmux kill-session -t "${SESSION_NAME}" >/dev/null 2>&1 || true

out="$(/Users/masayuki_otawara/bin/codex-kernel-guard doctor --all-runs)"
grep -Fq 'shared secrets status:' <<<"${out}"
grep -Fq 'OPENAI_API_KEY: present (' <<<"${out}"
grep -Fq 'project=fugue-orchestrator | purpose=tmux-handoff' <<<"${out}"
grep -Fq 'runtime=kernel' <<<"${out}"
grep -Fq "tmux_session=${SESSION_NAME}" <<<"${out}"
grep -Fq 'next_action=resume-implementation' <<<"${out}"
grep -Fq 'stale=true' <<<"${out}"

out="$(/Users/masayuki_otawara/bin/codex-kernel-guard doctor --run run-dr)"
grep -Fq 'run detail:' <<<"${out}"
grep -Fq 'run_id: run-dr' <<<"${out}"
grep -Fq 'runtime: kernel' <<<"${out}"
grep -Fq 'active_models: codex,glm,gemini-cli' <<<"${out}"
grep -Fq 'summary: Ready for MBP degraded continuation' <<<"${out}"

out="$(/Users/masayuki_otawara/bin/codex-kernel-guard recover-run run-dr)"
grep -Fq "tmux session: ${SESSION_NAME}" <<<"${out}"
grep -Fq 'codex thread: fugue-orchestrator:tmux-handoff' <<<"${out}"
grep -Fq 'strategy: continue-phase' <<<"${out}"
grep -Fq 'runtime: kernel' <<<"${out}"
grep -Fq "${SESSION_NAME}:main | bash ${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh launch run-dr C-m" "${FAKE_TMUX_LOG}"

windows="$(tmux list-windows -t "=${SESSION_NAME}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ "${windows}" == "main logs review ops" ]]

out="$(/Users/masayuki_otawara/bin/codex-kernel-guard doctor)"
grep -Fq 'active runs:' <<<"${out}"
grep -Fq 'project=fugue-orchestrator | purpose=tmux-handoff' <<<"${out}"
grep -Fq 'runtime=kernel' <<<"${out}"
grep -Fq "tmux_session=${SESSION_NAME}" <<<"${out}"
if grep -Fq 'stale=true' <<<"${out}"; then
  echo "default doctor output should not expose stale marker after recovery" >&2
  exit 1
fi

echo "kernel dr continuation check passed"
