#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="${ROOT_DIR}/.codex/prompts/vote.md"
ALIAS_FILE="${ROOT_DIR}/.codex/prompts/v.md"
CODEX_FILE="${ROOT_DIR}/CODEX.md"
README_FILE="${ROOT_DIR}/README.md"
GATE_WORKFLOW_FILE="${ROOT_DIR}/.github/workflows/fugue-orchestration-gate.yml"

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

assert_not_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "${needle}" "${path}"; then
    echo "[FAIL] ${label}: unexpected '${needle}' in ${path}" >&2
    failures=$((failures + 1))
  else
    echo "[PASS] ${label}" >&2
  fi
}

assert_files_equal() {
  local left="$1"
  local right="$2"
  local label="$3"
  if cmp -s "${left}" "${right}"; then
    echo "[PASS] ${label}" >&2
  else
    echo "[FAIL] ${label}: ${left} != ${right}" >&2
    failures=$((failures + 1))
  fi
}

vote_smoke_markers_present() {
  local output_file="$1"
  local smoke_marker="$2"
  grep -Fq 'Local consensus mode is active.' "${output_file}" \
    && grep -Fq "env -u RUN_CODEX_VOTE_SMOKE bash tests/test-codex-vote-prompt.sh" "${output_file}" \
    && grep -Fq 'Smoke verification: PASS' "${output_file}" \
    && grep -Fq "Smoke result marker: ${smoke_marker}" "${output_file}"
}

run_vote_smoke_with_timeout() {
  local timeout_sec="$1"
  local output_file="$2"
  local smoke_marker="$3"
  local vote_command="/vote SMOKE_RESULT_MARKER=${smoke_marker}"
  local cmd_pid start_ts now_ts cmd_status

  (
    codex exec -C "${ROOT_DIR}" "${vote_command}" >"${output_file}" 2>&1
  ) &
  cmd_pid="$!"
  start_ts="$(date +%s)"

  while kill -0 "${cmd_pid}" 2>/dev/null; do
    if vote_smoke_markers_present "${output_file}" "${smoke_marker}"; then
      kill "${cmd_pid}" 2>/dev/null || true
      wait "${cmd_pid}" 2>/dev/null || true
      return 0
    fi

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_sec )); then
      kill "${cmd_pid}" 2>/dev/null || true
      wait "${cmd_pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done

  cmd_status=0
  wait "${cmd_pid}" || cmd_status="$?"
  if vote_smoke_markers_present "${output_file}" "${smoke_marker}"; then
    return 0
  fi
  return "${cmd_status}"
}

assert_file "${PROMPT_FILE}"
assert_file "${ALIAS_FILE}"
assert_file "${CODEX_FILE}"
assert_file "${README_FILE}"
assert_file "${GATE_WORKFLOW_FILE}"

assert_files_equal "${PROMPT_FILE}" "${ALIAS_FILE}" "vote alias matches canonical prompt"
assert_contains "${PROMPT_FILE}" "preserve the current repo, task, and unfinished next step" "vote prompt preserves active work"
assert_contains "${PROMPT_FILE}" "record local consensus evidence for the current run before phase completion proceeds" "vote prompt records local consensus evidence"
assert_contains "${PROMPT_FILE}" "do not end with a summary-only response when concrete next work remains" "vote prompt forbids summary-only stop"
assert_contains "${PROMPT_FILE}" "maintain at least 2 materially distinct active lanes" "vote prompt requires >=2 active lanes"
assert_contains "${PROMPT_FILE}" "Local consensus mode is active." "vote prompt requires exact acknowledgement text"
assert_contains "${PROMPT_FILE}" "do not inspect CI unless explicitly asked later" "vote prompt forbids default CI inspection"
assert_contains "${PROMPT_FILE}" "SMOKE_RESULT_MARKER=<token>" "vote prompt supports smoke marker mode"
assert_contains "${PROMPT_FILE}" "env -u RUN_CODEX_VOTE_SMOKE bash tests/test-codex-vote-prompt.sh" "vote prompt defines local static-check smoke step"
assert_contains "${PROMPT_FILE}" "Smoke verification: PASS" "vote prompt defines smoke verification output"
assert_contains "${PROMPT_FILE}" "Smoke result marker: <token>" "vote prompt defines smoke result marker output"
assert_contains "${PROMPT_FILE}" "Treat \`/vote\` as local continuation, not GitHub handoff." "vote prompt marks local-only semantics"
assert_contains "${PROMPT_FILE}" "Reuse successful local auth or trust evidence across the run" "vote prompt reuses auth evidence"
assert_contains "${PROMPT_FILE}" "Do not post to GitHub or any external service." "vote prompt forbids external side effects"
assert_contains "${PROMPT_FILE}" "Do not ask for confirmation just to start local consensus mode." "vote prompt avoids startup confirmation"
assert_not_contains "${PROMPT_FILE}" "gh issue comment" "vote prompt does not post to GitHub"
assert_not_contains "${ALIAS_FILE}" "gh issue comment" "vote alias prompt does not post to GitHub"

assert_contains "${CODEX_FILE}" "/vote" "CODEX documents vote slash contract"
assert_contains "${CODEX_FILE}" "local consensus evidence" "CODEX documents vote evidence path"
assert_contains "${CODEX_FILE}" "vote-gh" "CODEX documents explicit GitHub handoff path"
assert_contains "${CODEX_FILE}" "runtime smoke on a fresh session" "CODEX documents runtime smoke path"
assert_contains "${README_FILE}" "Codex の \`/vote\` はローカル継続用の slash prompt" "README documents local vote semantics"
assert_contains "${README_FILE}" "local consensus evidence" "README documents vote evidence path"
assert_contains "${README_FILE}" "vote-gh" "README documents explicit GitHub vote path"
assert_contains "${README_FILE}" "RUN_CODEX_VOTE_SMOKE=1 bash tests/test-codex-vote-prompt.sh" "README documents smoke command"
assert_contains "${GATE_WORKFLOW_FILE}" "bash tests/test-codex-vote-prompt.sh" "orchestration gate runs vote prompt static contract"

if [[ "${RUN_CODEX_VOTE_SMOKE:-0}" == "1" ]]; then
  smoke_timeout_sec="${CODEX_VOTE_SMOKE_TIMEOUT_SEC:-90}"
  smoke_marker="VOTE_SMOKE_OK_$(date +%s)"
  smoke_output_file="$(mktemp)"
  smoke_status=0
  run_vote_smoke_with_timeout "${smoke_timeout_sec}" "${smoke_output_file}" "${smoke_marker}" || smoke_status="$?"
  smoke_output="$(cat "${smoke_output_file}")"
  if vote_smoke_markers_present "${smoke_output_file}" "${smoke_marker}"; then
    echo "[PASS] runtime smoke: /vote produced ack and post-ack marker output" >&2
  elif [[ "${smoke_status}" == "124" ]]; then
    echo "[FAIL] runtime smoke: /vote timed out after ${smoke_timeout_sec}s" >&2
    printf '%s\n' "${smoke_output}" >&2
    failures=$((failures + 1))
  else
    echo "[FAIL] runtime smoke: expected ack + smoke marker output not found" >&2
    printf '%s\n' "${smoke_output}" >&2
    failures=$((failures + 1))
  fi
  rm -f "${smoke_output_file}"
fi

if (( failures > 0 )); then
  echo "codex vote prompt check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "codex vote prompt check passed"
