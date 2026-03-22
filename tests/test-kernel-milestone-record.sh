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

echo "kernel milestone record check passed"
