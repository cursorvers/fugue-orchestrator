#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="${ROOT_DIR}/.codex/prompts/kernel.md"
CODEX_FILE="${ROOT_DIR}/CODEX.md"
README_FILE="${ROOT_DIR}/README.md"

failures=0

assert_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "[FAIL] missing file: ${path}" >&2
    failures=$((failures + 1))
  else
    echo "[PASS] file present: ${path}" >&2
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "${needle}" "${path}"; then
    echo "[PASS] ${label}" >&2
  else
    echo "[FAIL] ${label}: missing '${needle}' in ${path}" >&2
    failures=$((failures + 1))
  fi
}

assert_file "${PROMPT_FILE}"
assert_file "${CODEX_FILE}"
assert_file "${README_FILE}"

assert_contains "${PROMPT_FILE}" "maintain at least 3 materially distinct active lanes" "prompt requires >=3 active lanes"
assert_contains "${PROMPT_FILE}" "do not collapse, defer, or silently degrade to single-thread execution" "prompt forbids single-thread degradation"
assert_contains "${PROMPT_FILE}" "treat de-parallelization as a policy violation" "prompt marks de-parallelization as violation"
assert_contains "${PROMPT_FILE}" "launch at least 3 materially distinct subagents immediately before any substantive analysis" "prompt requires immediate subagent launch"
assert_contains "${PROMPT_FILE}" "standard bootstrap target is 6 concurrent lanes" "prompt requires six-lane default"
assert_contains "${PROMPT_FILE}" "Lane manifest:" "prompt requires lane manifest"
assert_contains "${PROMPT_FILE}" "currently active lanes, not planned lanes" "prompt forbids planned-lane manifest"
assert_contains "${PROMPT_FILE}" "Bootstrap target: 6 lanes (minimum 3)." "prompt requires bootstrap target line"

assert_contains "${CODEX_FILE}" "fresh Codex session started at the repository root and then \`/kernel\`" "CODEX documents fresh-session repo-root contract"
assert_contains "${CODEX_FILE}" "Hot reload is not guaranteed." "CODEX documents restart requirement"
assert_contains "${CODEX_FILE}" "runtime smoke on a fresh session" "CODEX documents runtime smoke path"
assert_contains "${CODEX_FILE}" "launch at least 3 active subagent lanes before the first acknowledgement" "CODEX documents subagent-first bootstrap"
assert_contains "${CODEX_FILE}" "normal operating target is 6 concurrent lanes" "CODEX documents six-lane default"
assert_contains "${CODEX_FILE}" "Lane manifest:" "CODEX documents lane manifest"
assert_contains "${CODEX_FILE}" "Bootstrap target: 6 lanes (minimum 3)." "CODEX documents bootstrap target"

assert_contains "${README_FILE}" "repo root で新規に開いた Codex セッションから \`/kernel\`" "README documents repo-root contract"
assert_contains "${README_FILE}" "hot reload は保証しません" "README documents hot reload limitation"
assert_contains "${README_FILE}" "RUN_CODEX_KERNEL_SMOKE=1 bash tests/test-codex-kernel-prompt.sh" "README documents smoke command"
assert_contains "${README_FILE}" "最低 3 本の active lane" "README documents minimum active lanes"
assert_contains "${README_FILE}" "6 列並列を基本形" "README documents six-lane default"
assert_contains "${README_FILE}" "Lane manifest:" "README documents lane manifest"
assert_contains "${README_FILE}" "Bootstrap target: 6 lanes (minimum 3)." "README documents bootstrap target"

if [[ "${RUN_CODEX_KERNEL_SMOKE:-0}" == "1" ]]; then
  smoke_output="$(codex exec -C "${ROOT_DIR}" "/kernel" 2>&1 || true)"
  lane_manifest_count="$(printf '%s\n' "${smoke_output}" | grep -Ec '^- .+: .+ - .+$' || true)"
  if grep -Eq 'Kernel orchestration is active (in|for) this session\.' <<<"${smoke_output}" \
    && grep -Fq 'Bootstrap target: 6 lanes (minimum 3).' <<<"${smoke_output}" \
    && grep -Fq 'Lane manifest:' <<<"${smoke_output}" \
    && [[ "${lane_manifest_count}" -ge 3 ]]; then
    echo "[PASS] runtime smoke: /kernel acknowledged in fresh session" >&2
  else
    echo "[FAIL] runtime smoke: /kernel acknowledgement missing" >&2
    printf '%s\n' "${smoke_output}" >&2
    failures=$((failures + 1))
  fi
fi

if (( failures > 0 )); then
  echo "codex kernel prompt check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "codex kernel prompt check passed"
