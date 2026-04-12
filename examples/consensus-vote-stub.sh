#!/bin/bash

# FUGUE Orchestrator - 3-Party Consensus Stub
#
# Demonstrates the consensus voting flow for dangerous operations.
# In production, each vote comes from a different model.
#
# Usage:
#   chmod +x consensus-vote-stub.sh
#   ./consensus-vote-stub.sh "rm -rf ./build" "Clean build artifacts"

OPERATION="${1:-dangerous operation}"
REASON="${2:-no reason given}"
SCRIPT_DIR="$(dirname "$0")"
DELEGATE="node ${SCRIPT_DIR}/delegate-stub.js"

echo "=== FUGUE 3-Party Consensus ==="
echo "Operation: ${OPERATION}"
echo "Reason: ${REASON}"
echo ""

# Level 1 Check: Is this system-destructive?
LEVEL1_KEYWORDS="production|main|master|rm -rf /|system|全削除"
if echo "${OPERATION}" | grep -qiE "${LEVEL1_KEYWORDS}"; then
  echo "[LEVEL 1] System-destructive operation detected."
  echo ">>> USER CONFIRMATION REQUIRED <<<"
  echo ""
  read -p "Do you approve this operation? (yes/no): " USER_APPROVAL
  if [ "${USER_APPROVAL}" != "yes" ]; then
    echo "Operation REJECTED by user."
    exit 2
  fi
  echo "User approved. Proceeding..."
  exit 0
fi

# Level 2: 3-Party Consensus
echo "[LEVEL 2] Running 3-party consensus..."
echo ""

TASK="Evaluate if this operation is safe to execute:
Operation: ${OPERATION}
Reason: ${REASON}
Respond with APPROVE, CONDITIONAL, or REJECT and a brief rationale."

# Vote 1: Claude (self-assessment, simulated here)
echo "  [1/3] Claude (Orchestrator): Evaluating..."
VOTE_CLAUDE="APPROVE"  # In production: Claude's own assessment
echo "         Vote: ${VOTE_CLAUDE}"

# Vote 2: Codex security-analyst
echo "  [2/3] Codex (Security): Evaluating..."
${DELEGATE} -a security-analyst -t "${TASK}" -p codex > /dev/null 2>&1
VOTE_CODEX=$?
VOTE_CODEX_RESULT=$([ ${VOTE_CODEX} -eq 0 ] && echo "APPROVE" || echo "REJECT")
echo "         Vote: ${VOTE_CODEX_RESULT}"

# Vote 3: GLM general-reviewer
echo "  [3/3] GLM (Reviewer): Evaluating..."
${DELEGATE} -a general-reviewer -t "${TASK}" -p glm > /dev/null 2>&1
VOTE_GLM=$?
VOTE_GLM_RESULT=$([ ${VOTE_GLM} -eq 0 ] && echo "APPROVE" || echo "REJECT")
echo "         Vote: ${VOTE_GLM_RESULT}"

echo ""

# Tally
APPROVE_COUNT=0
[ "${VOTE_CLAUDE}" = "APPROVE" ] && APPROVE_COUNT=$((APPROVE_COUNT + 1))
[ "${VOTE_CODEX_RESULT}" = "APPROVE" ] && APPROVE_COUNT=$((APPROVE_COUNT + 1))
[ "${VOTE_GLM_RESULT}" = "APPROVE" ] && APPROVE_COUNT=$((APPROVE_COUNT + 1))

echo "=== Verdict: ${APPROVE_COUNT}/3 approved ==="

if [ ${APPROVE_COUNT} -ge 3 ]; then
  echo "APPROVED: Execute immediately"
  exit 0
elif [ ${APPROVE_COUNT} -ge 2 ]; then
  echo "CONDITIONAL: Execute with logging"
  exit 0
elif [ ${APPROVE_COUNT} -ge 1 ]; then
  echo "REJECTED: Present alternatives"
  exit 1
else
  echo "BLOCKED: Full rejection"
  exit 1
fi
