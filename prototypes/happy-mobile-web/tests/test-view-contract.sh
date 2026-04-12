#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web"
HTML="$ROOT/index.html"

grep -q 'data-screen="happy"' "$HTML"
grep -q 'data-screen="now"' "$HTML"
grep -q 'data-screen="tasks"' "$HTML"
grep -q 'data-screen="alerts"' "$HTML"
grep -q 'data-screen="recover"' "$HTML"
grep -q 'Happy.app inside' "$HTML"
grep -q 'Task detail' "$HTML"
grep -q 'data-filter="in-progress"' "$HTML"
grep -q 'data-filter="needs-review"' "$HTML"
grep -q 'Kernel に送る' "$HTML"
grep -q 'Normalized intake packet' "$HTML"

echo "PASS [happy-mobile-view-contract]"
