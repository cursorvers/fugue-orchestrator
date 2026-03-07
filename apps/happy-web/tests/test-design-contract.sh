#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/masayuki/Dev/fugue-orchestrator/apps/happy-web"
HTML="$ROOT/index.html"
CSS="$ROOT/styles.css"
APP="$ROOT/src/app.js"

grep -q 'pulse-strip' "$HTML"
grep -q 'details-panel' "$HTML"
grep -q 'hero-route-row' "$HTML"
grep -q 'recover-actions' "$HTML"
grep -q 'recent-prompt' "$APP"
grep -q 'recover-card' "$CSS"
grep -q 'pulse-card' "$CSS"
grep -q 'hero-badge' "$CSS"

echo "PASS [apps-happy-web-design-contract]"
