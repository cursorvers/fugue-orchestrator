#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web"
JS="$ROOT/app.js"
HTML="$ROOT/index.html"

grep -q 'local-primary' "$JS"
grep -q 'fugue-bridge' "$JS"
grep -q 'phaseIndex' "$JS"
grep -q 'phaseTotal' "$JS"
grep -q 'progressConfidence' "$JS"
grep -q 'routeLabel' "$JS"
grep -q 'github-continuity' "$JS"
grep -q 'task_type' "$JS"
grep -q 'requested_route' "$JS"
grep -q 'client_timestamp' "$JS"
grep -q 'created_at' "$JS"
grep -q 'continuity-canary' "$HTML"
grep -q 'rollback-canary' "$HTML"
grep -q 'reroute-issue' "$HTML"
grep -q 'refresh-progress' "$HTML"
grep -q 'data-recover="status"' "$HTML"
grep -q 'Crow accepted' "$JS"

echo "PASS [happy-mobile-state-model]"
