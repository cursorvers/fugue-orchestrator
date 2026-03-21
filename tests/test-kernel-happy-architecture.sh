#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${ROOT_DIR}/docs/kernel-happy-app-single-front-architecture.md"

test -f "${DOC}"

for pattern in \
  "### 4.1 Happy" \
  "### 4.2 Now" \
  "### 4.3 Tasks" \
  "### 4.4 Alerts" \
  "### 4.5 Recover" \
  "Architecture Comparison" \
  "Simulation 1: quick bugfix from smartphone" \
  "Simulation 2: content task while away from desk" \
  "Simulation 3: local primary degrades mid-task" \
  "Simulation 4: rollback needed" \
  "Simulation 5: user checks progress only" \
  "Simulation 6: desktop/mobile split" \
  "one all-in-one mobile front" \
  "Happy.app" \
  "fugue-bridge"
do
  grep -q "${pattern}" "${DOC}"
done

echo "PASS [kernel-happy-architecture]"
