#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-auth-evidence.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUN_ID="auth-evidence-run"

path="$(bash "${SCRIPT}" path cursor-cli)"
[[ "${path}" == "${TMP_DIR}/state/auth-evidence/auth-evidence-run/cursor-cli.json" ]]

out="$(bash "${SCRIPT}" record cursor-cli ready logged-in)"
[[ "${out}" == "${path}" ]]
[[ -f "${path}" ]]

status="$(bash "${SCRIPT}" status cursor-cli)"
grep -Fq 'present: true' <<<"${status}"
grep -Fq 'state: ready' <<<"${status}"
grep -Fq 'note: logged-in' <<<"${status}"

echo "kernel auth evidence check passed"
