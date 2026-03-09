#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/masayuki/Dev/fugue-orchestrator/apps/happy-web"

grep -q '"display": "standalone"' "$ROOT/manifest.webmanifest"
grep -q 'serviceWorker.register' "$ROOT/src/app.js"
grep -q 'skipWaiting' "$ROOT/sw.js"
grep -q 'manifest.webmanifest' "$ROOT/index.html"

echo "PASS [apps-happy-web-pwa-shell]"
