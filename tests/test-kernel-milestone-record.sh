#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-milestone-record.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

RUNNER_SCRIPT="${TMP_DIR}/runner.sh"
LOG_FILE="${TMP_DIR}/runner.log"

cat > "${RUNNER_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${KERNEL_MILESTONE_RECORD_LOG}"
EOF
chmod +x "${RUNNER_SCRIPT}"

export KERNEL_RUN_ID="milestone-run"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="milestone-check"
export KERNEL_MILESTONE_RECORD_LOG="${LOG_FILE}"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/bootstrap"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}/approved"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/approved/runtime-workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/approved/runtime-receipts"

KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" phase plan

grep -Fq -- '--source kernel-phase-complete' "${LOG_FILE}" || {
  echo "plan phase should be auto-recorded" >&2
  exit 1
}
grep -Fq -- '--title fugue-orchestrator:milestone-check:plan' "${LOG_FILE}" || {
  echo "plan phase should include milestone title" >&2
  exit 1
}

: > "${LOG_FILE}"
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" phase critique

if [[ -s "${LOG_FILE}" ]]; then
  echo "critique phase should not be auto-recorded by default" >&2
  exit 1
fi

: > "${LOG_FILE}"
KERNEL_AUTO_MILESTONE_RECORDING=false \
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" phase implement

if [[ -s "${LOG_FILE}" ]]; then
  echo "milestone recording should skip when disabled" >&2
  exit 1
fi

: > "${LOG_FILE}"
ORCH_DRY_RUN=1 \
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" phase verify

if [[ -s "${LOG_FILE}" ]]; then
  echo "milestone recording should skip during dry-run" >&2
  exit 1
fi

: > "${LOG_FILE}"
KERNEL_AUTO_RECORD_NO_GHA=true \
KERNEL_AUTO_RECORD_DRY_RUN=true \
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" phase verify

grep -Fq -- '--no-gha' "${LOG_FILE}" || {
  echo "milestone recording should forward no-gha when requested" >&2
  exit 1
}
grep -Fq -- '--dry-run' "${LOG_FILE}" || {
  echo "milestone recording should forward dry-run when requested" >&2
  exit 1
}

rm -f "${LOG_FILE}"
KERNEL_AUTO_RECORD_NO_GHA=true \
KERNEL_CHECKPOINT_SAVE_MIN_INTERVAL_SEC=900 \
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" checkpoint "checkpoint summary"

grep -Fq -- '--source kernel-progress-save' "${LOG_FILE}" || {
  echo "checkpoint save should mirror through backup runner" >&2
  exit 1
}
grep -Fq -- '--title fugue-orchestrator:milestone-check:checkpoint' "${LOG_FILE}" || {
  echo "checkpoint save should include checkpoint title" >&2
  exit 1
}
grep -Fq -- '--summary checkpoint summary' "${LOG_FILE}" || {
  echo "checkpoint save should preserve summary" >&2
  exit 1
}

compact_path="${KERNEL_COMPACT_DIR}/milestone-run.json"
workspace_receipt_path="$(jq -r '.workspace_receipt_path' "${compact_path}")"
[[ -f "${workspace_receipt_path}" ]] || {
  echo "checkpoint save should refresh workspace receipt" >&2
  exit 1
}
grep -Fq 'checkpoint summary' "${compact_path}" || {
  echo "checkpoint save should update compact summary" >&2
  exit 1
}

before_lines="$(wc -l < "${LOG_FILE}" | tr -d ' ')"
KERNEL_AUTO_RECORD_NO_GHA=true \
KERNEL_CHECKPOINT_SAVE_MIN_INTERVAL_SEC=900 \
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" checkpoint "checkpoint summary ignored"
after_lines="$(wc -l < "${LOG_FILE}" | tr -d ' ')"
[[ "${before_lines}" == "${after_lines}" ]] || {
  echo "checkpoint save should be throttled by default" >&2
  exit 1
}

KERNEL_AUTO_RECORD_NO_GHA=true \
KERNEL_CHECKPOINT_SAVE_MIN_INTERVAL_SEC=900 \
KERNEL_CHECKPOINT_SAVE_FORCE=true \
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" checkpoint "checkpoint summary forced"
grep -Fq -- '--summary checkpoint summary forced' "${LOG_FILE}" || {
  echo "forced checkpoint save should bypass throttle" >&2
  exit 1
}

: > "${LOG_FILE}"
FAILING_RUNNER="${TMP_DIR}/failing-runner.sh"
cat > "${FAILING_RUNNER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 9
EOF
chmod +x "${FAILING_RUNNER}"

if KERNEL_AUTO_RECORD_NO_GHA=true \
  KERNEL_CHECKPOINT_SAVE_MIN_INTERVAL_SEC=900 \
  KERNEL_CHECKPOINT_SAVE_FORCE=true \
  KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${FAILING_RUNNER}" \
  bash "${SCRIPT}" checkpoint "checkpoint should fail"; then
  echo "checkpoint save should fail when mirror runner fails" >&2
  exit 1
fi

KERNEL_AUTO_RECORD_NO_GHA=true \
KERNEL_CHECKPOINT_SAVE_MIN_INTERVAL_SEC=900 \
KERNEL_CHECKPOINT_SAVE_FORCE=true \
KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${RUNNER_SCRIPT}" \
bash "${SCRIPT}" checkpoint "checkpoint after failure"
grep -Fq -- '--summary checkpoint after failure' "${LOG_FILE}" || {
  echo "checkpoint failure should not advance throttle stamp" >&2
  exit 1
}

echo "kernel milestone record check passed"
