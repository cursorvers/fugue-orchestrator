#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -q '"display": "standalone"' "$ROOT/manifest.webmanifest"
grep -q 'serviceWorker.register' "$ROOT/src/app.js"
grep -q 'skipWaiting' "$ROOT/sw.js"
grep -q 'manifest.webmanifest' "$ROOT/index.html"

echo "PASS [apps-happy-web-pwa-shell]"
