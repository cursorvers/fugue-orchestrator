#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_RUN_ID="compact-test"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="secret-plane"
export KERNEL_PHASE="plan"
export KERNEL_OWNER="codex"
export KERNEL_TMUX_SESSION="fugue-orchestrator:secret-plane"
export KERNEL_DECISIONS="use-keychain|mirror-github|keep-fugue-untouched|ignored"
export KERNEL_NEXT_ACTIONS="implement-loader|add-tests|run-dry-run|ignored"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"

bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${LEDGER_SCRIPT}" transition healthy "bootstrap-valid" >/dev/null

out="$(bash "${COMPACT_SCRIPT}" status)"
grep -Fq 'present: true' <<<"${out}"
grep -Fq 'project: fugue-orchestrator' <<<"${out}"
grep -Fq 'purpose: secret-plane' <<<"${out}"
grep -Fq 'phase: plan' <<<"${out}"
grep -Fq 'mode: healthy' <<<"${out}"
grep -Fq 'runtime: kernel' <<<"${out}"
grep -Fq 'session fingerprint:' <<<"${out}"
grep -Fq 'codex thread: fugue-orchestrator:secret-plane' <<<"${out}"
grep -Fq 'next action: implement-loader' <<<"${out}"
grep -Fq 'decisions: use-keychain | mirror-github | keep-fugue-untouched' <<<"${out}"

out="$(KERNEL_SUMMARY=$'line1\nline2\nline3\nline4' bash "${COMPACT_SCRIPT}" update manual_snapshot)"
grep -Fq 'summary: line1 || line2 || line3' <<<"${out}"

unset KERNEL_TMUX_SESSION
export KERNEL_RUN_ID="compact-test-a"
out="$(bash "${COMPACT_SCRIPT}" update status_changed "parallel a")"
session_a="$(jq -r '.tmux_session' "${KERNEL_COMPACT_DIR}/compact-test-a.json")"
fingerprint_a="$(jq -r '.session_fingerprint' "${KERNEL_COMPACT_DIR}/compact-test-a.json")"
thread_a="$(jq -r '.codex_thread_title' "${KERNEL_COMPACT_DIR}/compact-test-a.json")"
runtime_a="$(jq -r '.runtime' "${KERNEL_COMPACT_DIR}/compact-test-a.json")"
[[ "${session_a}" == fugue-orchestrator__secret-plane__* ]]
[[ -n "${fingerprint_a}" && "${fingerprint_a}" != "null" ]]
[[ "${thread_a}" == fugue-orchestrator:secret-plane:* ]]
[[ "${runtime_a}" == "kernel" ]]

export KERNEL_RUN_ID="compact-test-b"
export KERNEL_RUNTIME="fugue"
out="$(bash "${COMPACT_SCRIPT}" update status_changed "parallel b")"
session_b="$(jq -r '.tmux_session' "${KERNEL_COMPACT_DIR}/compact-test-b.json")"
fingerprint_b="$(jq -r '.session_fingerprint' "${KERNEL_COMPACT_DIR}/compact-test-b.json")"
thread_b="$(jq -r '.codex_thread_title' "${KERNEL_COMPACT_DIR}/compact-test-b.json")"
runtime_b="$(jq -r '.runtime' "${KERNEL_COMPACT_DIR}/compact-test-b.json")"
[[ "${session_b}" == fugue-orchestrator__secret-plane__* ]]
[[ -n "${fingerprint_b}" && "${fingerprint_b}" != "${fingerprint_a}" ]]
[[ "${thread_b}" == fugue-orchestrator:secret-plane:* ]]
[[ "${runtime_b}" == "fugue" ]]
if [[ "${session_a}" == "${session_b}" ]]; then
  echo "parallel runs with the same purpose must not share tmux_session" >&2
  exit 1
fi
unset KERNEL_RUNTIME

FAKE_BIN="${TMP_DIR}/fake-bin"
mkdir -p "${FAKE_BIN}"
cat >"${FAKE_BIN}/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "display-message" && "${2:-}" == "-p" && "${3:-}" == "#S" ]]; then
  printf 'current-shared-session\n'
  exit 0
fi
exit 1
EOF
chmod +x "${FAKE_BIN}/tmux"

export PATH="${FAKE_BIN}:$PATH"
export TMUX="yes"
export KERNEL_RUN_ID="compact-test-c"
out="$(bash "${COMPACT_SCRIPT}" update status_changed "parallel c")"
session_c="$(jq -r '.tmux_session' "${KERNEL_COMPACT_DIR}/compact-test-c.json")"
if [[ "${session_c}" == "current-shared-session" ]]; then
  echo "new runs inside tmux must mint a dedicated session instead of reusing the current session" >&2
  exit 1
fi
[[ "${session_c}" == fugue-orchestrator__secret-plane__* ]]
unset TMUX

echo "kernel compact artifact check passed"
