#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${ROOT_DIR}/docs/kernel-context-governor.md"

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
  "## 8. Legacy Claude-side compatibility" \
  "handoff_target=fugue-bridge" \
  "## 11. Acceptance criteria"
do
  grep -q "${pattern}" "${DOC}"
done

echo "PASS [kernel-context-governor]"
