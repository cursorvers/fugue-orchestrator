#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/gha24"
DOC="${ROOT_DIR}/docs/gha24-mainframe-flow.md"
CREATE_FUGUE="${ROOT_DIR}/scripts/local/create-fugue-issue.sh"
DISPATCH_MAINFRAME="${ROOT_DIR}/scripts/local/dispatch-mainframe.sh"

failed=0

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "${needle}" "${file}"; then
    echo "PASS [${label}]"
  else
    echo "FAIL [${label}]" >&2
    failed=$((failed + 1))
  fi
}

bash -n "${SCRIPT}"
echo "PASS [gha24-shell-syntax]"
bash -n "${CREATE_FUGUE}"
echo "PASS [create-fugue-issue-shell-syntax]"
bash -n "${DISPATCH_MAINFRAME}"
echo "PASS [dispatch-mainframe-shell-syntax]"

assert_contains "${SCRIPT}" "--confirm-implement" "gha24 exposes explicit critical confirmation flag"
assert_contains "${SCRIPT}" 'CONFIRM_IMPLEMENT=false' "gha24 defaults confirmation to false"
assert_contains "${SCRIPT}" 'if [[ "${CONFIRM_IMPLEMENT}" == "true" ]]; then' "gha24 gates implement-confirmed label"
assert_contains "${SCRIPT}" '$( [[ "${CONFIRM_IMPLEMENT}" == "true" ]] && echo "confirmed" || echo "pending" )' "gha24 writes pending by default"
assert_contains "${CREATE_FUGUE}" "--confirm-implement" "create-fugue exposes explicit critical confirmation flag"
assert_contains "${CREATE_FUGUE}" 'CONFIRM_IMPLEMENT=false' "create-fugue defaults confirmation to false"
assert_contains "${DISPATCH_MAINFRAME}" "--confirm-implement" "dispatch-mainframe exposes explicit critical confirmation flag"
assert_contains "${DISPATCH_MAINFRAME}" 'CONFIRM_IMPLEMENT=false' "dispatch-mainframe defaults confirmation to false"
assert_contains "${DOC}" "Implement mode adds implementation intent only" "docs say implement intent only"
assert_contains "${DOC}" 'confirmed` is required only for critical/high-risk implementation execution' "docs scope confirmation to critical/high-risk"

if awk '
  /REQUIRED_LABELS=\(/ { in_labels=1; next }
  in_labels && /\)/ { in_labels=0 }
  in_labels && /implement-confirmed/ { found=1 }
  END { exit found ? 0 : 1 }
' "${CREATE_FUGUE}" || awk '
  /REQUIRED_LABELS=\(/ { in_labels=1; next }
  in_labels && /\)/ { in_labels=0 }
  in_labels && /implement-confirmed/ { found=1 }
  END { exit found ? 0 : 1 }
' "${DISPATCH_MAINFRAME}"; then
  echo "FAIL [local required labels exclude implement-confirmed]" >&2
  failed=$((failed + 1))
else
  echo "PASS [local required labels exclude implement-confirmed]"
fi

if (( failed > 0 )); then
  echo "=== Results: failed ${failed} ===" >&2
  exit 1
fi

echo "=== Results: all passed ==="
