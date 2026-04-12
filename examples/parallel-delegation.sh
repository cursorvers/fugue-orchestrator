#!/bin/bash

# FUGUE Orchestrator - Parallel Delegation Example
#
# Demonstrates running multiple delegation scripts in parallel
# (e.g., pre-commit check: code-reviewer + security-analyst)
#
# Usage:
#   chmod +x parallel-delegation.sh
#   ./parallel-delegation.sh "Review the auth module" src/auth.ts

TASK="${1:-Review this code}"
FILE="${2:-}"
SCRIPT_DIR="$(dirname "$0")"
DELEGATE="node ${SCRIPT_DIR}/delegate-stub.js"

echo "=== FUGUE Parallel Delegation ==="
echo "Task: ${TASK}"
echo "File: ${FILE:-<none>}"
echo ""

# Run code-reviewer (GLM) and security-analyst (Codex) in parallel
echo "--- Starting parallel evaluation ---"

${DELEGATE} -a code-reviewer -t "${TASK}" -f "${FILE}" -p glm &
PID_REVIEW=$!

${DELEGATE} -a security-analyst -t "${TASK}" -f "${FILE}" -p codex &
PID_SECURITY=$!

# Wait for both to complete
wait ${PID_REVIEW}
EXIT_REVIEW=$?

wait ${PID_SECURITY}
EXIT_SECURITY=$?

echo ""
echo "=== Results ==="
echo "Code Review:     $([ ${EXIT_REVIEW} -eq 0 ] && echo 'PASS' || echo 'FAIL')"
echo "Security Audit:  $([ ${EXIT_SECURITY} -eq 0 ] && echo 'PASS' || echo 'FAIL')"

# Combined verdict
if [ ${EXIT_REVIEW} -eq 0 ] && [ ${EXIT_SECURITY} -eq 0 ]; then
  echo "Verdict: APPROVE"
  exit 0
else
  echo "Verdict: FIX_REQUIRED"
  exit 1
fi
