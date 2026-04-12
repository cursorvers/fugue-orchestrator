#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUDGET_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
GLM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "display-message" ]]; then
  echo "session-alpha"
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/bin/tmux"

export PATH="${TMP_DIR}/bin:${PATH}"
export TMUX="stub"
unset KERNEL_RUN_ID KERNEL_OPTIONAL_LANE_RUN_ID KERNEL_GLM_RUN_ID

out="$(cd "${ROOT_DIR}" && bash "${BUDGET_SCRIPT}" status)"
grep -Fq 'run id: kernel-workspace:session-alpha' <<<"${out}"

out="$(cd "${ROOT_DIR}" && bash "${GLM_SCRIPT}" status)"
grep -Fq 'run id: kernel-workspace:session-alpha' <<<"${out}"

echo "kernel run id resolution check passed"
