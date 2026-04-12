#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web"
MANIFEST="$ROOT/manifest.webmanifest"
SW="$ROOT/sw.js"
HTML="$ROOT/index.html"

grep -q '"display": "standalone"' "$MANIFEST"
grep -q '"theme_color": "#111827"' "$MANIFEST"
grep -q 'serviceWorker.register' "$ROOT/app.js"
grep -q 'skipWaiting' "$SW"
grep -q 'manifest.webmanifest' "$HTML"
grep -q 'select id="urgency"' "$HTML"
grep -q 'packet-preview' "$HTML"

echo "PASS [happy-mobile-pwa-shell]"
