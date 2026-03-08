#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="${ROOT_DIR}/.codex/prompts/kernel.md"
ALIAS_FILE="${ROOT_DIR}/.codex/prompts/k.md"
CODEX_FILE="${ROOT_DIR}/CODEX.md"
README_FILE="${ROOT_DIR}/README.md"
GATE_FILE="${ROOT_DIR}/.github/workflows/fugue-orchestration-gate.yml"

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
assert_file "${ALIAS_FILE}"
assert_file "${CODEX_FILE}"
assert_file "${README_FILE}"
assert_file "${GATE_FILE}"

assert_contains "${PROMPT_FILE}" "maintain at least 6 materially distinct active lanes" "prompt requires >=6 active lanes"
assert_contains "${PROMPT_FILE}" "do not collapse, defer, or silently degrade to single-thread execution" "prompt forbids single-thread degradation"
assert_contains "${PROMPT_FILE}" "treat de-parallelization as a policy violation" "prompt marks de-parallelization as violation"
assert_contains "${PROMPT_FILE}" "launch at least 6 materially distinct subagents immediately before any substantive analysis" "prompt requires immediate subagent launch"
assert_contains "${PROMPT_FILE}" "bootstrap target is at least 6 concurrent lanes" "prompt requires six-lane minimum"
assert_contains "${PROMPT_FILE}" "Lane manifest:" "prompt requires lane manifest"
assert_contains "${PROMPT_FILE}" "currently active lanes, not planned lanes" "prompt forbids planned-lane manifest"
assert_contains "${PROMPT_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "prompt requires bootstrap target line"
assert_contains "${ALIAS_FILE}" "Treat \`/k\` as a local one-word alias for \`/kernel\`." "alias prompt identifies /k semantics"
assert_contains "${ALIAS_FILE}" "launch at least 6 materially distinct subagents immediately before any substantive analysis" "alias prompt requires immediate subagent launch"
assert_contains "${ALIAS_FILE}" "Lane manifest:" "alias prompt requires lane manifest"
assert_contains "${ALIAS_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "alias prompt requires bootstrap target line"

assert_contains "${CODEX_FILE}" "fresh Codex session started at the repository root and then \`/kernel\`" "CODEX documents fresh-session repo-root contract"
assert_contains "${CODEX_FILE}" "\`/k\` is a local one-word alias for \`/kernel\`" "CODEX documents /k alias"
assert_contains "${CODEX_FILE}" "supported local adapter path is \`kernel\` or \`codex-prompt-launch kernel\`" "CODEX documents local adapter path"
assert_contains "${CODEX_FILE}" "local alias prompt for one-word chat-box startup is \`.codex/prompts/k.md\`" "CODEX documents alias prompt path"
assert_contains "${CODEX_FILE}" "Treat \`codex-kernel-guard launch\` as the local execution authority" "CODEX documents guard authority"
assert_contains "${CODEX_FILE}" "Hot reload is not guaranteed." "CODEX documents restart requirement"
assert_contains "${CODEX_FILE}" "Bare \`/kernel\` inside the Codex chat UI is not a local SLO path" "CODEX documents bare slash boundary"
assert_contains "${CODEX_FILE}" "runtime smoke on a fresh session" "CODEX documents runtime smoke path"
assert_contains "${CODEX_FILE}" "launch at least 6 active subagent lanes before the first acknowledgement" "CODEX documents subagent-first bootstrap"
assert_contains "${CODEX_FILE}" "minimum operating target is 6 or more concurrent lanes" "CODEX documents six-lane minimum"
assert_contains "${CODEX_FILE}" "Lane manifest:" "CODEX documents lane manifest"
assert_contains "${CODEX_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "CODEX documents bootstrap target"

assert_contains "${README_FILE}" "repo root で新規に開いた Codex セッションから \`/kernel\`" "README documents repo-root contract"
assert_contains "${README_FILE}" "chat 欄から 1語で起動したい場合の local alias は \`/k\`" "README documents /k alias"
assert_contains "${README_FILE}" "ローカルでの推奨実行経路は \`kernel\` または \`codex-prompt-launch kernel\`" "README documents launcher adapter path"
assert_contains "${README_FILE}" "1語 alias の prompt は [\`.codex/prompts/k.md\`]" "README documents alias prompt path"
assert_contains "${README_FILE}" "ローカル実行契約の authority は shell wrapper ではなく \`codex-kernel-guard launch\`" "README documents guard authority"
assert_contains "${README_FILE}" "hot reload は保証しません" "README documents hot reload limitation"
assert_contains "${README_FILE}" "bare \`/kernel\` は Codex chat UI の upstream 実装に依存" "README documents bare slash boundary"
assert_contains "${README_FILE}" "RUN_CODEX_KERNEL_SMOKE=1 bash tests/test-codex-kernel-prompt.sh" "README documents smoke command"
assert_contains "${README_FILE}" "最低 6 本の active lane" "README documents minimum active lanes"
assert_contains "${README_FILE}" "6 列以上の並列を最低形" "README documents six-lane minimum"
assert_contains "${README_FILE}" "Lane manifest:" "README documents lane manifest"
assert_contains "${README_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "README documents bootstrap target"
assert_contains "${GATE_FILE}" "'.codex/prompts/k.md'" "gate watches /k alias prompt"

if [[ "${RUN_CODEX_KERNEL_SMOKE:-0}" == "1" ]]; then
  smoke_output="$(codex exec -C "${ROOT_DIR}" "/kernel" 2>&1 || true)"
  lane_manifest_count="$(printf '%s\n' "${smoke_output}" | grep -Ec '^- .+: .+ - .+$' || true)"
  if grep -Eq 'Kernel orchestration is active (in|for) this session\.' <<<"${smoke_output}" \
    && grep -Fq 'Bootstrap target: 6+ lanes (minimum 6).' <<<"${smoke_output}" \
    && grep -Fq 'Lane manifest:' <<<"${smoke_output}" \
    && [[ "${lane_manifest_count}" -ge 6 ]]; then
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
