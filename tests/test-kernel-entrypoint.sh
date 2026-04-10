#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/kernel-entrypoint.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/repo" "${TMP_DIR}/state" "${TMP_DIR}/compact"

PROMPT_LOG="${TMP_DIR}/prompt.log"
FOUR_PANE_LOG="${TMP_DIR}/4pane.log"
TMUX_STATE_FILE="${TMP_DIR}/tmux-sessions.txt"
touch "${TMUX_STATE_FILE}"

cat > "${HOME}/bin/codex-prompt-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PROMPT_LOG}"
EOF
chmod +x "${HOME}/bin/codex-prompt-launch"

cat > "${TMP_DIR}/repo/.git-stub" <<'EOF'
stub
EOF

fake_git_dir="${TMP_DIR}/bin"
mkdir -p "${fake_git_dir}"
cat > "${fake_git_dir}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-C" ]]; then
  cwd="${2:-}"
  shift 2 || true
else
  cwd="${PWD}"
fi
if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--show-toplevel" ]]; then
  case "${cwd}" in
    "${ROOT_DIR}"|${ROOT_DIR}/*)
      printf '%s\n' "${ROOT_DIR}"
      exit 0
      ;;
    *)
      exit 1
      ;;
  esac
fi
exit 1
EOF
chmod +x "${fake_git_dir}/git"

cat > "${fake_git_dir}/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    target="${3:-}"
    target="${target#=}"
    grep -Fxq "${target}" "${TMUX_STATE_FILE}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${fake_git_dir}/tmux"

stub_4pane="${TMP_DIR}/stub-4pane.sh"
cat > "${stub_4pane}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FOUR_PANE_LOG}"
EOF
chmod +x "${stub_4pane}"

cat > "${TMP_DIR}/state/4pane-active.json" <<'EOF'
{"run_id":"run-active","tmux_session":"kernel__active"}
EOF
cat > "${TMP_DIR}/workspace-receipt-active.json" <<'EOF'
{"ok":true}
EOF
recent_active_ts="$(python3 - <<'PY'
import datetime
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
cat > "${TMP_DIR}/compact/run-active.json" <<'EOF'
{"run_id":"run-active","tmux_session":"kernel__active","updated_at":"ACTIVE_UPDATED_AT_PLACEHOLDER","workspace_receipt_path":"WORKSPACE_ACTIVE_PLACEHOLDER"}
EOF
python3 - "${TMP_DIR}/compact/run-active.json" "${TMP_DIR}/workspace-receipt-active.json" "${recent_active_ts}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("WORKSPACE_ACTIVE_PLACEHOLDER", sys.argv[2])
text = text.replace("ACTIVE_UPDATED_AT_PLACEHOLDER", sys.argv[3])
path.write_text(text, encoding="utf-8")
PY
printf '%s\n' 'kernel__active' >> "${TMUX_STATE_FILE}"

export PATH="${fake_git_dir}:${PATH}"
export PROMPT_LOG
export FOUR_PANE_LOG
export TMUX_STATE_FILE
export ROOT_DIR
export KERNEL_CODEX_PROMPT_LAUNCH_BIN="${HOME}/bin/codex-prompt-launch"
export KERNEL_4PANE_LAUNCH_SCRIPT="${stub_4pane}"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"

(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}" spec-sync focus-text
)
grep -Fq -- '--purpose spec-sync focus-text' "${FOUR_PANE_LOG}"

: > "${FOUR_PANE_LOG}"
(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}" "決済APIのタイムアウトを調査して原因を特定"
)
grep -Fq -- '--purpose api' "${FOUR_PANE_LOG}"
grep -Fq -- '決済APIのタイムアウトを調査して原因を特定' "${FOUR_PANE_LOG}"

: > "${FOUR_PANE_LOG}"
(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}" 決済API の タイムアウト を 調査
)
grep -Fq -- '--purpose api' "${FOUR_PANE_LOG}"
grep -Fq -- '決済API の タイムアウト を 調査' "${FOUR_PANE_LOG}"

: > "${FOUR_PANE_LOG}"
(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}"
)
grep -Fq -- '--run run-active' "${FOUR_PANE_LOG}"

: > "${FOUR_PANE_LOG}"
rm -f "${TMP_DIR}/state/4pane-active.json"
cat > "${TMP_DIR}/workspace-receipt.json" <<'EOF'
{"ok":true}
EOF
recent_latest_ts="$(python3 - <<'PY'
import datetime
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
cat > "${TMP_DIR}/compact/run-latest.json" <<'EOF'
{"run_id":"run-latest","tmux_session":"kernel__latest","updated_at":"LATEST_UPDATED_AT_PLACEHOLDER","workspace_receipt_path":"WORKSPACE_RECEIPT_PLACEHOLDER"}
EOF
python3 - "${TMP_DIR}/compact/run-latest.json" "${TMP_DIR}/workspace-receipt.json" "${recent_latest_ts}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("WORKSPACE_RECEIPT_PLACEHOLDER", sys.argv[2])
text = text.replace("LATEST_UPDATED_AT_PLACEHOLDER", sys.argv[3])
path.write_text(text, encoding="utf-8")
PY
printf '%s\n' 'kernel__latest' >> "${TMUX_STATE_FILE}"
(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}"
)
grep -Fq -- '--run run-latest' "${FOUR_PANE_LOG}"

: > "${FOUR_PANE_LOG}"
: > "${TMUX_STATE_FILE}"
(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}"
)
grep -Fq -- '--purpose interactive' "${FOUR_PANE_LOG}"

: > "${FOUR_PANE_LOG}"
export KERNEL_AUTO_4PANE=false
(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}" review-only
)
grep -Fq 'kernel review-only' "${PROMPT_LOG}"
unset KERNEL_AUTO_4PANE

: > "${PROMPT_LOG}"
export TMUX=/tmp/tmux-sock
(
  cd "${ROOT_DIR}"
  bash "${SCRIPT}" inside-tmux
)
grep -Fq 'kernel inside-tmux' "${PROMPT_LOG}"
unset TMUX

echo "kernel entrypoint check passed"
