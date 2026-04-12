#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-session-name.sh"

out="$(KERNEL_PROJECT='fugue-orchestrator' KERNEL_PURPOSE='secret plane' bash "${SCRIPT}" slug)"
[[ "${out}" == "fugue-orchestrator__secret-plane" ]]

out="$(KERNEL_PROJECT='fugue-orchestrator' KERNEL_PURPOSE='secret plane' KERNEL_SESSION_SHORT_ID='7f2a' bash "${SCRIPT}" slug)"
[[ "${out}" == "fugue-orchestrator__secret-plane__7f2a" ]]

out="$(KERNEL_PROJECT='fugue-orchestrator' KERNEL_PURPOSE='secret plane' bash "${SCRIPT}" label)"
[[ "${out}" == "fugue-orchestrator:secret plane" ]]

echo "kernel session name check passed"
