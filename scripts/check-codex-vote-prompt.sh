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
assert_contains "${PROMPT_FILE}" "continue until the task reaches a real completion point" "vote prompt requires end-to-end continuation"
assert_contains "${PROMPT_FILE}" "do not end with a summary-only response when concrete next work remains" "vote prompt forbids summary-only stop"
assert_contains "${PROMPT_FILE}" "if the user explicitly asks for production verification, treat it as an execution obligation" "vote prompt treats production verification as execution obligation"
assert_contains "${PROMPT_FILE}" "maintain at least 2 materially distinct active lanes" "vote prompt requires >=2 active lanes"
assert_contains "${PROMPT_FILE}" "start with a lane plan that names at least 3 distinct active model families or providers" "vote prompt requires 3-family lane plan"
assert_contains "${PROMPT_FILE}" 'the default operating council is `Codex + Claude + GLM`' "vote prompt defines default trio council"
assert_contains "${PROMPT_FILE}" 'keep `Codex + Claude + GLM` active through the full task lifecycle' "vote prompt requires trio across lifecycle"
assert_contains "${PROMPT_FILE}" 'do not treat 2-lane execution as sufficient when `Codex + Claude + GLM` are available' "vote prompt rejects 2-lane downgrade when trio is available"
assert_contains "${PROMPT_FILE}" "before major edits, define requirements, constraints, acceptance criteria, failure modes, and stop conditions; treat that packet as a hard gate for implementation" "vote prompt requires requirements packet gate"
assert_contains "${PROMPT_FILE}" "if the user explicitly asks for production verification, the requirements packet must define the live workflow or runtime path to exercise" "vote prompt requires production verification packet"
assert_contains "${PROMPT_FILE}" "kernel handoff mode" "vote prompt defines kernel handoff mode"
assert_contains "${PROMPT_FILE}" "skip duplicate redesign rounds" "vote prompt skips duplicate redesign rounds in handoff mode"
assert_contains "${PROMPT_FILE}" "maintain at least 6 materially distinct active lanes for kernel handoff mode" "vote prompt raises lane floor for handoff mode"
assert_contains "${PROMPT_FILE}" "provider priority for ordinary execution is fixed-cost first" "vote prompt defines fixed-cost-first execution policy"
assert_contains "${PROMPT_FILE}" "Copilot CLI is the low-cost continuity fallback" "vote prompt defines Copilot fallback role"
assert_contains "${PROMPT_FILE}" "Gemini/xAI are metered specialist lanes reserved for \`overflow\` or \`tie-break\` only" "vote prompt restricts metered providers"
assert_contains "${PROMPT_FILE}" "record \`metered_reason\`, \`fallback_used\`, \`fallback_provider\`, and \`fallback_reason\`" "vote prompt requires metered fallback evidence"
assert_contains "${PROMPT_FILE}" "Local consensus mode is active." "vote prompt requires exact acknowledgement text"
assert_contains "${PROMPT_FILE}" "Do not inspect CI unless explicitly asked later" "vote prompt forbids default CI inspection"
assert_contains "${PROMPT_FILE}" "If the user explicitly asks for production verification, live workflow inspection is mandatory and overrides the default no-CI rule" "vote prompt overrides no-CI rule for production verification"
assert_contains "${PROMPT_FILE}" "SMOKE_RESULT_MARKER=<token>" "vote prompt supports smoke marker mode"
assert_contains "${PROMPT_FILE}" "env -u RUN_CODEX_VOTE_SMOKE bash tests/test-codex-vote-prompt.sh" "vote prompt defines local static-check smoke step"
assert_contains "${PROMPT_FILE}" "Smoke verification: PASS" "vote prompt defines smoke verification output"
assert_contains "${PROMPT_FILE}" "Smoke result marker: <token>" "vote prompt defines smoke result marker output"
assert_contains "${PROMPT_FILE}" "Treat \`/vote\` as local continuation, not GitHub issue-comment handoff." "vote prompt marks local-only semantics"
assert_contains "${PROMPT_FILE}" "Do not create or edit GitHub issues, pull requests, review comments, or issue comments." "vote prompt forbids GitHub comment and PR or issue edits"
assert_contains "${PROMPT_FILE}" "Backup-only GitHub Actions dispatch or repository_dispatch for task or audit logging is allowed, and when the user explicitly asks for production verification, live rerun or workflow_dispatch needed to complete that verification is also allowed." "vote prompt allows verification-scoped GHA dispatch"
assert_contains "${PROMPT_FILE}" "Do not post to any other external service." "vote prompt forbids other external side effects"
assert_contains "${PROMPT_FILE}" "Do not ask for confirmation just to start local consensus mode." "vote prompt avoids startup confirmation"
assert_contains "${PROMPT_FILE}" "determine Claude and GLM lane availability from the configured bridge or runtime path, not from ad-hoc local binary checks alone" "vote prompt uses bridge-authoritative provider checks"
assert_contains "${PROMPT_FILE}" "a missing local \`glm\` command does not prove GLM is unavailable" "vote prompt rejects local glm binary heuristic"
assert_contains "${PROMPT_FILE}" "a failed direct \`claude\` CLI attempt does not prove Claude is unavailable" "vote prompt rejects single direct claude failure heuristic"
assert_contains "${PROMPT_FILE}" "prefer bridge-authoritative probes or current-run bootstrap evidence" "vote prompt prefers bridge evidence"
assert_contains "${PROMPT_FILE}" "before returning \`BLOCKED\` for missing Claude or GLM, run the recovery matrix in the current run" "vote prompt requires recovery matrix before blocked"
assert_contains "${PROMPT_FILE}" "only return \`BLOCKED\` for missing Claude or GLM after that recovery matrix has been attempted and failed with a concrete reason" "vote prompt requires recovery failure before blocked"
assert_contains "${PROMPT_FILE}" 'when returning `BLOCKED`, name the missing lane, the attempted bridge-authoritative probe, and the concrete failure reason' "vote prompt requires explicit blocked evidence"
assert_contains "${PROMPT_FILE}" "for production verification tasks, local tests or readiness checks alone are insufficient to claim success" "vote prompt forbids local-only production PASS claim"
assert_contains "${PROMPT_FILE}" "run exactly 3 refinement rounds before major edits" "vote prompt requires 3 refinement rounds"
assert_contains "${PROMPT_FILE}" '`Plan -> Parallel Simulation -> Critical Review -> Problem Fix -> Replan`' "vote prompt defines refinement order"
assert_contains "${PROMPT_FILE}" "\`Parallel Simulation\` and \`Critical Review\` are hard gates and cannot be skipped" "vote prompt enforces hard gates"
assert_contains "${PROMPT_FILE}" "if simulation or critical review exposes a design flaw or contradiction, repair and replan before implementation resumes" "vote prompt forces repair before implementation"
assert_contains "${PROMPT_FILE}" "if simulation or critical review exposes an unresolved external blocker, run the recovery matrix before stopping" "vote prompt requires recovery before blocking on external blockers"
assert_contains "${PROMPT_FILE}" "for production verification tasks, return \`BLOCKED\` only when the live rerun or verification path has been attempted and failed with an external blocker" "vote prompt narrows BLOCKED for production verification"
assert_contains "${PROMPT_FILE}" "continue with council-backed implementation until the task is actually complete" "vote prompt requires council-backed completion"
assert_contains "${PROMPT_FILE}" "when production verification is requested, do not stop after a patch, push, dispatch, or partial log read if concrete execution remains" "vote prompt forbids stopping early during production verification"
assert_contains "${PROMPT_FILE}" '`Implementer Proposal -> Critic Challenge -> Integrator Decision -> Applied Change -> Verification`' "vote prompt defines implementation dialogue order"
assert_contains "${PROMPT_FILE}" "record lane evidence at finish" "vote prompt requires finish evidence"
assert_contains "${PROMPT_FILE}" "do not request approval for exploratory convenience; exhaust local workspace evidence first" "vote prompt forbids exploratory approval requests"
assert_contains "${PROMPT_FILE}" "ordinary implementation, analysis, testing, refactoring, and safe local workspace writes must proceed without user confirmation" "vote prompt forbids approval for ordinary work"
assert_contains "${PROMPT_FILE}" "mass deletion" "vote prompt calls out mass deletion as critical approval boundary"
assert_contains "${PROMPT_FILE}" "only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task" "vote prompt requires strict approval necessity"
assert_contains "${PROMPT_FILE}" "before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY" "vote prompt requires lane quiescence before approval prompts"
assert_contains "${PROMPT_FILE}" "do not surface an approval prompt while background Codex activity is still emitting output into the same terminal" "vote prompt forbids approval prompts during active background output"
assert_contains "${PROMPT_FILE}" "if lane quiescence cannot be achieved promptly, fail closed with a one-line \`quiescence_timeout\` status instead of surfacing the approval prompt" "vote prompt fail-closes when quiescence cannot be established"
assert_not_contains "${PROMPT_FILE}" "gh issue comment" "vote prompt does not post to GitHub"
assert_not_contains "${ALIAS_FILE}" "gh issue comment" "vote alias prompt does not post to GitHub"

matrix_stderr_file="$(mktemp)"
matrix_payload="$("${ROOT_DIR}/scripts/lib/build-agent-matrix.sh" \
  --engine subscription \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode enhanced \
  --glm-subagent-mode paired \
  --allow-glm-in-subscription true \
  --dual-main-signal true \
  --format json 2>"${matrix_stderr_file}")" || {
  echo "[FAIL] vote topology simulation failed" >&2
  if [[ -s "${matrix_stderr_file}" ]]; then
    cat "${matrix_stderr_file}" >&2
  fi
  failures=$((failures + 1))
  matrix_payload=""
}
if [[ -n "${matrix_payload}" ]]; then
  if echo "${matrix_payload}" | jq -e '
    (.matrix.include | any(.provider == "codex"))
    and (.matrix.include | any(.provider == "claude"))
    and (.matrix.include | any(.provider == "glm"))
  ' >/dev/null 2>&1; then
    echo "[PASS] vote topology simulation includes codex + claude + glm" >&2
  else
    echo "[FAIL] vote topology simulation missing codex/claude/glm baseline trio" >&2
    failures=$((failures + 1))
  fi
fi
rm -f "${matrix_stderr_file}"

matrix_optional_payload="$("${ROOT_DIR}/scripts/lib/build-agent-matrix.sh" \
  --engine subscription \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode enhanced \
  --glm-subagent-mode paired \
  --allow-glm-in-subscription true \
  --wants-gemini true \
  --wants-xai true \
  --format json)"
if echo "${matrix_optional_payload}" | jq -e '
  ([.matrix.include[] | select(.provider == "gemini" or .provider == "xai")] | length) == 0
' >/dev/null 2>&1; then
  echo "[PASS] vote topology suppresses metered lanes without reason" >&2
else
  echo "[FAIL] vote topology unexpectedly allowed metered lanes without reason" >&2
  failures=$((failures + 1))
fi

matrix_metered_payload="$("${ROOT_DIR}/scripts/lib/build-agent-matrix.sh" \
  --engine subscription \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode enhanced \
  --glm-subagent-mode paired \
  --allow-glm-in-subscription true \
  --wants-gemini true \
  --metered-reason tie-break \
  --format json)"
if echo "${matrix_metered_payload}" | jq -e '
  (.metered_reason == "tie-break")
  and ([.matrix.include[] | select(.provider == "gemini" and .metered_reason == "tie-break")] | length) == 1
' >/dev/null 2>&1; then
  echo "[PASS] vote topology preserves metered lane reason" >&2
else
  echo "[FAIL] vote topology did not preserve metered lane reason" >&2
  failures=$((failures + 1))
fi

assert_contains "${ROOT_DIR}/rules/dangerous-permission-consensus.md" "Mass file deletion (10+)" "dangerous-operation rule treats mass deletion as level 1"
assert_not_contains "${ROOT_DIR}/rules/dangerous-permission-consensus.md" "Claude may execute alone only when" "dangerous-operation rule forbids single-actor level 1 override"

assert_contains "${CODEX_FILE}" "/vote" "CODEX documents vote slash contract"
assert_contains "${CODEX_FILE}" "vote-gh" "CODEX documents explicit GitHub handoff path"
assert_contains "${CODEX_FILE}" 'baseline council is `Codex + Claude + GLM`' "CODEX documents trio baseline"
assert_contains "${CODEX_FILE}" "run 3 refinement rounds" "CODEX documents 3 refinement rounds"
assert_contains "${CODEX_FILE}" "approval-prompt quiescence rule applies to \`/vote\` and \`/v\`" "CODEX documents vote approval quiescence"
assert_contains "${CODEX_FILE}" "do not request approval for exploratory convenience" "CODEX documents approval necessity rule"
assert_contains "${CODEX_FILE}" "runtime smoke on a fresh session" "CODEX documents runtime smoke path"
assert_contains "${CODEX_FILE}" "local smoke or static checks are not sufficient to claim production PASS" "CODEX documents no local-only production PASS rule"
assert_contains "${CODEX_FILE}" "When the user explicitly asks for production verification, live workflow inspection is part of the required completion path" "CODEX documents production verification no-CI override"
assert_contains "${README_FILE}" "Codex の \`/vote\` はローカル継続用の slash prompt" "README documents local vote semantics"
assert_contains "${README_FILE}" "\`Codex + Claude + GLM\` の 3 系統 council" "README documents trio baseline"
assert_contains "${README_FILE}" "3 回の refinement round" "README documents 3 refinement rounds"
assert_contains "${README_FILE}" "\`/vote\` で本番確認を求められた場合、local continuation の責務は patch -> push -> workflow_dispatch or rerun -> artifact / log inspection -> PASS 判定まで含みます。" "README documents vote production verification obligation"
assert_contains "${README_FILE}" "verification 用の実行経路であり、GitHub handoff や issue comment 投稿とは別扱いです。" "README separates verification dispatch from GitHub handoff"
assert_contains "${README_FILE}" "\`/vote\` で \`BLOCKED\` を返してよいのは、live rerun / verification path を実際に試し" "README narrows vote BLOCKED for production verification"
assert_contains "${README_FILE}" "ユーザーが本番確認を明示した場合、live workflow / artifact inspection は完遂条件の一部" "README documents production verification no-CI override"
assert_contains "${README_FILE}" "vote-gh" "README documents explicit GitHub vote path"
assert_contains "${README_FILE}" "\`/vote\` / \`/v\` でも approval prompt を伴う操作に入る前は" "README documents vote approval quiescence"
assert_contains "${README_FILE}" "便宜的な探索のために approval を要求してはいけません" "README documents approval necessity rule"
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
