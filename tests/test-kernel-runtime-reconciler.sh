#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
RECONCILER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-reconciler.sh"
TMP_DIR="$(mktemp -d)"
out=""
claim_json=""

cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    echo "kernel runtime reconciler debug:" >&2
    [[ -n "${out}" ]] && printf 'last reconcile output: %s\n' "${out}" >&2
    [[ -n "${claim_json}" ]] && printf 'last claim status: %s\n' "${claim_json}" >&2
  fi
  rm -rf "${TMP_DIR}"
  exit "${rc}"
}

trap cleanup EXIT

export KERNEL_SUBSTRATE_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/state/runtime-ledger.json"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/runtime-receipts"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export TMUX_BIN="${TMP_DIR}/bin/tmux"

mkdir -p "${KERNEL_COMPACT_DIR}"
mkdir -p "$(dirname "${TMUX_BIN}")"

cat >"${TMUX_BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  has-session)
    if [[ "${3:-}" == "=live-session" ]]; then
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${TMUX_BIN}"

mark_claim_stale() {
  local claim_path="${1:?claim path required}"
  python3 - "${claim_path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["updated_at_epoch"] = 0
data["updated_at"] = "2026-04-01T00:00:00Z"
path.write_text(json.dumps(data))
PY
}

mark_compact_stale() {
  local compact_path="${1:?compact path required}"
  python3 - "${compact_path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["updated_at"] = "2026-04-01T00:00:00Z"
data.pop("tmux_session", None)
path.write_text(json.dumps(data))
PY
}

bash "${CLAIM_SCRIPT}" claim --project demo --issue-number 8 --run-id run-8 --command-string "printf later" >/dev/null
bash "${CLAIM_SCRIPT}" set-state --identity 'demo#8' --state running --reason "started" >/dev/null
workspace_receipt_path="$(KERNEL_RUN_ID=run-8 bash "${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh" write run-8)"
compact_path="$(KERNEL_RUN_ID=run-8 bash "${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh" path run-8)"
cat >"${compact_path}" <<EOF
{"run_id":"run-8","project":"demo","purpose":"issue-8","runtime":"kernel","updated_at":"2026-04-01T00:00:00Z"}
EOF

orphan_compact_path="${KERNEL_COMPACT_DIR}/orphan-run.json"
cat >"${orphan_compact_path}" <<EOF
{"run_id":"orphan-run","project":"demo","purpose":"orphan","runtime":"kernel","updated_at":"2026-04-01T00:00:00Z"}
EOF

queue_json='{"items":[{"project":"demo","issue_number":8,"authorized":true,"eligible":false,"reason":"human approval required","command_string":"printf later"}]}'
out="$(bash "${RECONCILER_SCRIPT}" reconcile --queue-json "${queue_json}" --ttl-seconds 60)"
[[ "$(jq -r '.stopped' <<<"${out}")" == "1" ]]
[[ "$(jq -r '.archived_files' <<<"${out}")" == "1" ]]
[[ "$(jq -r '.orphan_archived' <<<"${out}")" == "1" ]]
[[ "$(jq -r '.archived_runs | index("orphan-run") != null' <<<"${out}")" == "true" ]]

claim_json="$(bash "${CLAIM_SCRIPT}" status --identity 'demo#8')"
[[ "$(jq -r '.claim.status' <<<"${claim_json}")" == "awaiting_human" ]]
[[ "$(jq -r '.claim.stop_reason' <<<"${claim_json}")" == "human approval required" ]]

bash "${CLAIM_SCRIPT}" set-state --identity 'demo#8' --state running --reason "restarted" >/dev/null
claim_path="$(bash "${CLAIM_SCRIPT}" path --identity 'demo#8')"
mark_claim_stale "${claim_path}"
mark_compact_stale "${compact_path}"

out="$(bash "${RECONCILER_SCRIPT}" reconcile --queue-json '{"items":[]}' --ttl-seconds 60 --archive-ttl-seconds 60)"
released="$(jq -r '.released' <<<"${out}")"
[[ "${released}" == "0" || "${released}" == "1" ]]
[[ "$(jq -r '.archived_files' <<<"${out}")" == "2" ]]
[[ "$(jq -r '.orphan_archived' <<<"${out}")" == "0" ]]
[[ "$(jq -r '.archived_runs | index("run-8") != null' <<<"${out}")" == "true" ]]
claim_json="$(bash "${CLAIM_SCRIPT}" status --identity 'demo#8')"
[[ "$(jq -r '.claim.status' <<<"${claim_json}")" == "terminal" ]]
[[ "$(jq -r '.claim.claim_active' <<<"${claim_json}")" == "false" ]]
[[ ! -f "${compact_path}" ]]
[[ ! -f "${workspace_receipt_path}" ]]
[[ ! -f "${orphan_compact_path}" ]]
find "${KERNEL_SUBSTRATE_STATE_ROOT}/archive/runtime-reconciler/compact" -type f | grep -q 'run-8'
find "${KERNEL_SUBSTRATE_STATE_ROOT}/archive/runtime-reconciler/workspace-receipts" -type f | grep -q 'run-8'
find "${KERNEL_SUBSTRATE_STATE_ROOT}/archive/runtime-reconciler/compact" -type f | grep -q 'orphan-run'

bash "${CLAIM_SCRIPT}" claim --project demo --issue-number 9 --run-id run-9 --command-string "printf tmux" >/dev/null
bash "${CLAIM_SCRIPT}" set-state --identity 'demo#9' --state running --reason "started" >/dev/null
workspace_receipt_tmux="$(KERNEL_RUN_ID=run-9 bash "${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh" write run-9)"
compact_tmux="$(KERNEL_RUN_ID=run-9 bash "${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh" path run-9)"
cat >"${compact_tmux}" <<EOF
{"run_id":"run-9","project":"demo","purpose":"issue-9","runtime":"kernel","tmux_session":"live-session","updated_at":"2026-04-01T00:00:00Z"}
EOF
claim_path="$(bash "${CLAIM_SCRIPT}" path --identity 'demo#9')"
mark_claim_stale "${claim_path}"

out="$(bash "${RECONCILER_SCRIPT}" reconcile --queue-json '{"items":[]}' --ttl-seconds 60 --archive-ttl-seconds 60)"
[[ "$(jq -r '.released' <<<"${out}")" == "0" ]]
claim_json="$(bash "${CLAIM_SCRIPT}" status --identity 'demo#9')"
[[ "$(jq -r '.claim.claim_active' <<<"${claim_json}")" == "true" ]]
[[ -f "${compact_tmux}" ]]
[[ -f "${workspace_receipt_tmux}" ]]

bash "${CLAIM_SCRIPT}" claim --project demo --issue-number 10 --run-id run-10 --command-string "printf fresh" >/dev/null
bash "${CLAIM_SCRIPT}" set-state --identity 'demo#10' --state running --reason "started" >/dev/null
workspace_receipt_fresh="$(KERNEL_RUN_ID=run-10 bash "${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh" write run-10)"
compact_fresh="$(KERNEL_RUN_ID=run-10 bash "${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh" path run-10)"
cat >"${compact_fresh}" <<EOF
{"run_id":"run-10","project":"demo","purpose":"issue-10","runtime":"kernel","updated_at":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"}
EOF
claim_path="$(bash "${CLAIM_SCRIPT}" path --identity 'demo#10')"
mark_claim_stale "${claim_path}"

out="$(bash "${RECONCILER_SCRIPT}" reconcile --queue-json '{"items":[]}' --ttl-seconds 60 --archive-ttl-seconds 60)"
[[ "$(jq -r '.released' <<<"${out}")" == "0" ]]
claim_json="$(bash "${CLAIM_SCRIPT}" status --identity 'demo#10')"
[[ "$(jq -r '.claim.claim_active' <<<"${claim_json}")" == "true" ]]
[[ -f "${compact_fresh}" ]]
[[ -f "${workspace_receipt_fresh}" ]]

echo "kernel runtime reconciler check passed"
