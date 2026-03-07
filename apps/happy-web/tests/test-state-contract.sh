#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/masayuki/Dev/fugue-orchestrator/apps/happy-web"
STATE="$ROOT/src/kernel-state.js"
APP="$ROOT/src/app.js"
HTML="$ROOT/index.html"

grep -q 'source: "happy-app"' "$STATE"
grep -q 'task_type' "$STATE"
grep -q 'requested_recovery_action' "$STATE"
grep -q 'created_at' "$STATE"
grep -q 'is_primary' "$STATE"
grep -q 'continuity-canary' "$HTML"
grep -q 'rollback-canary' "$HTML"
grep -q 'reroute-issue' "$HTML"
grep -q 'refresh-progress' "$HTML"
grep -q 'task-sheet' "$HTML"
grep -q 'phase_index' "$STATE"
grep -q 'buildIntakePacket' "$STATE"
grep -q 'openTaskSheet' "$APP"

echo "PASS [apps-happy-web-state-contract]"
