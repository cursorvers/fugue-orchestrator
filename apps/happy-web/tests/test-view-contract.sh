#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTML="$ROOT/index.html"

grep -q 'data-screen="happy"' "$HTML"
grep -q 'data-screen="now"' "$HTML"
grep -q 'data-screen="tasks"' "$HTML"
grep -q 'data-screen="alerts"' "$HTML"
grep -q 'data-screen="recover"' "$HTML"
grep -q 'Task detail' "$HTML"
grep -q 'sheet-session' "$HTML"
grep -q 'Normalized intake packet' "$HTML"
grep -q 'Recent events' "$HTML"
grep -q 'Happy.app inside' "$HTML"

echo "PASS [apps-happy-web-view-contract]"
