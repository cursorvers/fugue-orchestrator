#!/usr/bin/env bash
set -euo pipefail

DOC="/Users/masayuki/Dev/fugue-orchestrator/docs/kernel-context-governor.md"

test -f "${DOC}"

for pattern in \
  "## 2. Budget bands" \
  "green" \
  "amber" \
  "red" \
  "hard-stop" \
  "## 4. Lane budgets" \
  "codex-main" \
  "claude-reviewer" \
  "glm-reviewer" \
  "## 7. Mobile rules" \
  "## 8. FUGUE compatibility" \
  "handoff_target=fugue-bridge" \
  "## 11. Acceptance criteria"
do
  grep -q "${pattern}" "${DOC}"
done

echo "PASS [kernel-context-governor]"
