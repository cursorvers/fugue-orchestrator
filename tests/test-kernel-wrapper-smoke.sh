#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat >"${TMP_DIR}/bin/gemini" <<'EOF'
#!/usr/bin/env bash
echo "gemini-wrapper:$*"
EOF

cat >"${TMP_DIR}/bin/cursor" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "agent" && "${2:-}" == "status" ]]; then
  echo "Logged in as wrapper-test@example.com"
  exit 0
fi
if [[ "${1:-}" == "agent" ]]; then
  shift
fi
echo "cursor-wrapper:$*"
EOF

cat >"${TMP_DIR}/bin/copilot" <<'EOF'
#!/usr/bin/env bash
echo "copilot-wrapper:$*"
EOF

cat >"${TMP_DIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi
if [[ "${1:-}" == "copilot" ]]; then
  shift
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  echo "gh-copilot-wrapper:$*"
  exit 0
fi
exit 0
EOF

chmod +x "${TMP_DIR}/bin/gemini" "${TMP_DIR}/bin/cursor" "${TMP_DIR}/bin/copilot" "${TMP_DIR}/bin/gh"

export PATH="${TMP_DIR}/bin:${PATH}"
export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/ledger.json"
export KERNEL_OPTIONAL_LANE_LOCK_DIR="${TMP_DIR}/ledger.lock"
export KERNEL_RUN_ID="wrapper-smoke"
export KERNEL_GEMINI_DAILY_SOFT_CAP=5
export KERNEL_GEMINI_PER_RUN_SOFT_CAP=1
export KERNEL_CURSOR_MONTHLY_SOFT_CAP=5
export KERNEL_CURSOR_PER_RUN_SOFT_CAP=1
export KERNEL_COPILOT_MONTHLY_SOFT_CAP=5
export KERNEL_COPILOT_PER_RUN_SOFT_CAP=1
export KERNEL_COPILOT_AUTOPILOT_ALLOWED=false

out="$(bash /Users/masayuki_otawara/bin/kgemini test)"
grep -Fq 'gemini-wrapper:test' <<<"${out}"

out="$(bash /Users/masayuki_otawara/bin/kcursor --print test)"
grep -Fq 'cursor-wrapper:--print test' <<<"${out}"

out="$(bash /Users/masayuki_otawara/bin/kcopilot autopilot 2>&1 || true)"
grep -Fq 'copilot-cli autopilot/agent mode is disabled' <<<"${out}"

out="$(PATH="${TMP_DIR}/bin:/opt/homebrew/bin:/usr/bin:/bin" KERNEL_COPILOT_BIN=gh bash /Users/masayuki_otawara/bin/kcopilot -p test)"
grep -Fq 'gh-copilot-wrapper:-p test' <<<"${out}"

status="$(bash "${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh" status)"
grep -Fq 'gemini-cli: day 1/5, run 1/1' <<<"${status}"
grep -Fq 'cursor-cli: month 1/5, run 1/1' <<<"${status}"
grep -Fq 'copilot-cli: month 1/5, run 1/1' <<<"${status}"

echo "kernel wrapper smoke check passed"
