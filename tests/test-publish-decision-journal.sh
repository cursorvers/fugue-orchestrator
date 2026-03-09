#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/publish-decision-journal.sh"
WORKFLOW="${ROOT_DIR}/.github/workflows/kernel-decision-journal.yml"

bash -n "${SCRIPT}"
grep -Fq 'Kernel Decision Journal' "${SCRIPT}"
grep -Fq 'apps/happy-web/' "${SCRIPT}"
grep -Fq 'prototypes/happy-mobile-web/' "${SCRIPT}"
grep -Fq 'workflow_dispatch:' "${WORKFLOW}"
grep -Fq 'push:' "${WORKFLOW}"
grep -Fq 'apps/happy-web/**' "${WORKFLOW}"

echo "PASS [publish-decision-journal]"
