#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="${ROOT_DIR}/.codex/prompts/kernel.md"
ALIAS_FILE="${ROOT_DIR}/.codex/prompts/k.md"
CODEX_FILE="${ROOT_DIR}/CODEX.md"
README_FILE="${ROOT_DIR}/README.md"
GATE_FILE="${ROOT_DIR}/.github/workflows/fugue-orchestration-gate.yml"

failures=0
if [[ -n "${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_SECONDS+x}" ]]; then
  claude_bootstrap_timeout_sec="${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_SECONDS}"
elif [[ -n "${KERNEL_BOOTSTRAP_LANE_TIMEOUT_SECONDS+x}" ]]; then
  claude_bootstrap_timeout_sec="${KERNEL_BOOTSTRAP_LANE_TIMEOUT_SECONDS}"
else
  claude_bootstrap_timeout_sec=60
fi
if [[ -n "${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_STEP_SECONDS+x}" ]]; then
  claude_bootstrap_timeout_step_sec="${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_STEP_SECONDS}"
elif [[ -n "${KERNEL_BOOTSTRAP_CLAUDE_TIMEOUT_SECONDS+x}" || -n "${KERNEL_BOOTSTRAP_LANE_TIMEOUT_SECONDS+x}" ]]; then
  claude_bootstrap_timeout_step_sec=0
else
  claude_bootstrap_timeout_step_sec=30
fi
bootstrap_max_attempts="${KERNEL_BOOTSTRAP_MAX_ATTEMPTS:-3}"
bootstrap_backoff_sec="${KERNEL_BOOTSTRAP_RETRY_BACKOFF_SECONDS:-2}"
computed_smoke_timeout_sec=$(( claude_bootstrap_timeout_sec * bootstrap_max_attempts + claude_bootstrap_timeout_step_sec * bootstrap_max_attempts * (bootstrap_max_attempts - 1) / 2 + bootstrap_backoff_sec * (bootstrap_max_attempts - 1) + 25 ))
smoke_timeout_sec="${CODEX_KERNEL_SMOKE_TIMEOUT_SEC:-${computed_smoke_timeout_sec}}"

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
assert_contains "${PROMPT_FILE}" "launch at least 6 planning lanes tagged" "prompt requires 6 planning lanes"
assert_contains "${PROMPT_FILE}" "The first planning round must define requirements, constraints, acceptance criteria, failure modes, and stop conditions." "prompt requires round-1 requirements definition"
assert_contains "${PROMPT_FILE}" "In the same first planning round, define the completion proof and the external dependencies needed to reach it." "prompt requires completion proof and dependency definition"
assert_contains "${PROMPT_FILE}" "If the user explicitly asks to verify production behavior, treat production verification as an execution obligation, not a reporting task." "prompt treats production verification as execution obligation"
assert_contains "${PROMPT_FILE}" "Treat that planning packet as a hard gate." "prompt treats planning packet as hard gate"
assert_contains "${PROMPT_FILE}" "Launch at least 3 fast simulation lanes tagged" "prompt requires 3 simulation lanes"
assert_contains "${PROMPT_FILE}" "Prefer \`codex-spark\`" "prompt prefers codex-spark simulation"
assert_contains "${PROMPT_FILE}" "simulation validation is mandatory before implementation" "prompt requires simulation validation gate"
assert_contains "${PROMPT_FILE}" "run the recovery matrix first: re-probe the missing provider or dependency, promote the approved fallback provider, restore the lane floor with sidecars, and record exact errors" "prompt requires recovery matrix before blocked"
assert_contains "${PROMPT_FILE}" "if the environment cannot sustain 6 active lanes, first attempt lane replacement and sidecar backfill" "prompt requires lane recovery before fail-closed"
assert_contains "${PROMPT_FILE}" "Repeat the plan -> simulate -> critique -> repair -> replan loop 3 times by default" "prompt requires 3 redesign rounds"
assert_contains "${PROMPT_FILE}" "hand off into \`/vote\` as fast local continuation for implementation" "prompt hands off to /vote for implementation"
assert_contains "${PROMPT_FILE}" "After implementation, run cross-model quality review" "prompt requires post-implementation QA"
assert_contains "${PROMPT_FILE}" "if the user explicitly asks for production verification, the completion proof must name the live workflow, dispatch or rerun command, artifact or log path, and the exact PASS fields required before reporting success" "prompt requires explicit production verification completion proof"
assert_contains "${PROMPT_FILE}" "when production verification is requested, do not stop after a patch, design memo, push, dispatch, or partial log read if concrete execution remains" "prompt forbids stopping early during production verification"
assert_contains "${PROMPT_FILE}" "for production verification tasks, local tests or readiness checks alone are insufficient to claim success" "prompt forbids local-only production PASS claim"
assert_contains "${PROMPT_FILE}" "for production verification tasks, \`BLOCKED\` is valid only when the live rerun or verification path has been attempted and failed with an external blocker" "prompt narrows BLOCKED for production verification"
assert_contains "${PROMPT_FILE}" "provider priority for the ordinary \`/kernel\` loop is fixed-cost first" "prompt defines cost-aware provider priority"
assert_contains "${PROMPT_FILE}" "Copilot CLI is the low-marginal-cost continuity helper" "prompt defines Copilot as low-cost continuity helper"
assert_contains "${PROMPT_FILE}" "Gemini/xAI are metered specialist lanes reserved for \`overflow\` or \`tie-break\`" "prompt restricts Gemini/xAI to metered reasons"
assert_contains "${PROMPT_FILE}" "pass kernel handoff mode plus the active cost-policy snapshot" "prompt requires cost snapshot handoff to /vote"
assert_contains "${PROMPT_FILE}" "record \`metered_reason\`, \`fallback_used\`, \`fallback_provider\`, and \`fallback_reason\`" "prompt requires metered fallback evidence"
assert_contains "${PROMPT_FILE}" "Codex, Claude, GLM, Copilot CLI, and Gemini CLI" "prompt requires multi-agent core families"
assert_contains "${PROMPT_FILE}" "Codex is the orchestrator and integration layer." "prompt requires Codex orchestrator role"
assert_contains "${PROMPT_FILE}" "\`codex-multi-agents\` as the default Codex fan-out substrate" "prompt requires codex-multi-agents substrate"
assert_contains "${PROMPT_FILE}" "\`claude-code-agent-teams\` as the default Claude delegation substrate" "prompt requires claude-code-agent-teams substrate"
assert_contains "${PROMPT_FILE}" "delegate to Claude and GLM as real peer lanes" "prompt requires Claude and GLM peer delegation"
assert_contains "${PROMPT_FILE}" "do not treat subagents, \`codex-multi-agents\`, or \`claude-code-agent-teams\` alone as sufficient replacement" "prompt forbids substrate-only replacement"
assert_contains "${PROMPT_FILE}" "Lane manifest:" "prompt requires lane manifest"
assert_contains "${PROMPT_FILE}" "currently active lanes, not planned lanes" "prompt forbids planned-lane manifest"
assert_contains "${PROMPT_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "prompt requires bootstrap target line"
assert_contains "${PROMPT_FILE}" "Do not inspect the repository before bootstrap" "prompt forbids repo inspection before bootstrap"
assert_contains "${PROMPT_FILE}" "do not read \`README.md\`, \`CODEX.md\`, \`AGENTS.md\`, \`docs/**\`, \`.fugue/**\`" "prompt forbids pre-bootstrap doc tours"
assert_contains "${PROMPT_FILE}" "The first useful output for a fresh \`/kernel\` start is the acknowledgement and live lane manifest, not a repository summary." "prompt prioritizes ack over repo summary"
assert_contains "${PROMPT_FILE}" "If the user explicitly asks for production verification, live workflow inspection is mandatory and overrides the default no-CI rule" "prompt overrides no-CI rule for production verification"
assert_contains "${PROMPT_FILE}" "during bootstrap and local analysis, do not request approval for exploratory convenience; exhaust local workspace evidence first" "prompt forbids exploratory approval requests during bootstrap"
assert_contains "${PROMPT_FILE}" "only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task" "prompt requires strict approval necessity"
assert_contains "${PROMPT_FILE}" "before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY" "prompt requires lane quiescence before approval prompts"
assert_contains "${PROMPT_FILE}" "do not surface an approval prompt while background Codex activity is still emitting output into the same terminal" "prompt forbids approval prompts during active background output"
assert_contains "${PROMPT_FILE}" "if lane quiescence cannot be achieved promptly, fail closed with a one-line \`quiescence_timeout\` status instead of surfacing the approval prompt" "prompt fail-closes when quiescence cannot be established"
assert_contains "${PROMPT_FILE}" "low-touch autonomous development" "prompt documents low-touch autonomy"
assert_contains "${ALIAS_FILE}" "Treat \`/k\` as a local one-word alias for \`/kernel\`." "alias prompt identifies /k semantics"
assert_contains "${ALIAS_FILE}" "launch at least 6 materially distinct subagents immediately before any substantive analysis" "alias prompt requires immediate subagent launch"
assert_contains "${ALIAS_FILE}" "launch at least 6 planning lanes tagged" "alias prompt requires 6 planning lanes"
assert_contains "${ALIAS_FILE}" "The first planning round must define requirements, constraints, acceptance criteria, failure modes, and stop conditions." "alias prompt requires round-1 requirements definition"
assert_contains "${ALIAS_FILE}" "In the same first planning round, define the completion proof and the external dependencies needed to reach it." "alias prompt requires completion proof and dependency definition"
assert_contains "${ALIAS_FILE}" "If the user explicitly asks to verify production behavior, treat production verification as an execution obligation, not a reporting task." "alias prompt treats production verification as execution obligation"
assert_contains "${ALIAS_FILE}" "Treat that planning packet as a hard gate." "alias prompt treats planning packet as hard gate"
assert_contains "${ALIAS_FILE}" "Launch at least 3 fast simulation lanes tagged" "alias prompt requires 3 simulation lanes"
assert_contains "${ALIAS_FILE}" "Prefer \`codex-spark\`" "alias prompt prefers codex-spark simulation"
assert_contains "${ALIAS_FILE}" "simulation validation is mandatory before implementation" "alias prompt requires simulation validation gate"
assert_contains "${ALIAS_FILE}" "run the recovery matrix first: re-probe the missing provider or dependency, promote the approved fallback provider, restore the lane floor with sidecars, and record exact errors" "alias prompt requires recovery matrix before blocked"
assert_contains "${ALIAS_FILE}" "if the environment cannot sustain 6 active lanes, first attempt lane replacement and sidecar backfill" "alias prompt requires lane recovery before fail-closed"
assert_contains "${ALIAS_FILE}" "Repeat the plan -> simulate -> critique -> repair -> replan loop 3 times by default" "alias prompt requires 3 redesign rounds"
assert_contains "${ALIAS_FILE}" "hand off into \`/vote\` as fast local continuation for implementation" "alias prompt hands off to /vote for implementation"
assert_contains "${ALIAS_FILE}" "After implementation, run cross-model quality review" "alias prompt requires post-implementation QA"
assert_contains "${ALIAS_FILE}" "if the user explicitly asks for production verification, the completion proof must name the live workflow, dispatch or rerun command, artifact or log path, and the exact PASS fields required before reporting success" "alias prompt requires explicit production verification completion proof"
assert_contains "${ALIAS_FILE}" "when production verification is requested, do not stop after a patch, design memo, push, dispatch, or partial log read if concrete execution remains" "alias prompt forbids stopping early during production verification"
assert_contains "${ALIAS_FILE}" "for production verification tasks, local tests or readiness checks alone are insufficient to claim success" "alias prompt forbids local-only production PASS claim"
assert_contains "${ALIAS_FILE}" "for production verification tasks, \`BLOCKED\` is valid only when the live rerun or verification path has been attempted and failed with an external blocker" "alias prompt narrows BLOCKED for production verification"
assert_contains "${ALIAS_FILE}" "provider priority for the ordinary \`/kernel\` loop is fixed-cost first" "alias prompt defines cost-aware provider priority"
assert_contains "${ALIAS_FILE}" "Copilot CLI is the low-marginal-cost continuity helper" "alias prompt defines Copilot as low-cost continuity helper"
assert_contains "${ALIAS_FILE}" "Gemini/xAI are metered specialist lanes reserved for \`overflow\` or \`tie-break\`" "alias prompt restricts Gemini/xAI to metered reasons"
assert_contains "${ALIAS_FILE}" "pass kernel handoff mode plus the active cost-policy snapshot" "alias prompt requires cost snapshot handoff to /vote"
assert_contains "${ALIAS_FILE}" "record \`metered_reason\`, \`fallback_used\`, \`fallback_provider\`, and \`fallback_reason\`" "alias prompt requires metered fallback evidence"
assert_contains "${ALIAS_FILE}" "Codex, Claude, GLM, Copilot CLI, and Gemini CLI" "alias prompt requires multi-agent core families"
assert_contains "${ALIAS_FILE}" "Codex is the orchestrator and integration layer." "alias prompt requires Codex orchestrator role"
assert_contains "${ALIAS_FILE}" "\`codex-multi-agents\` as the default Codex fan-out substrate" "alias prompt requires codex-multi-agents substrate"
assert_contains "${ALIAS_FILE}" "\`claude-code-agent-teams\` as the default Claude delegation substrate" "alias prompt requires claude-code-agent-teams substrate"
assert_contains "${ALIAS_FILE}" "delegate to Claude and GLM as real peer lanes" "alias prompt requires Claude and GLM peer delegation"
assert_contains "${ALIAS_FILE}" "do not treat subagents, \`codex-multi-agents\`, or \`claude-code-agent-teams\` alone as sufficient replacement" "alias prompt forbids substrate-only replacement"
assert_contains "${ALIAS_FILE}" "Lane manifest:" "alias prompt requires lane manifest"
assert_contains "${ALIAS_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "alias prompt requires bootstrap target line"
assert_contains "${ALIAS_FILE}" "Do not inspect the repository before bootstrap" "alias prompt forbids repo inspection before bootstrap"
assert_contains "${ALIAS_FILE}" "An empty focus is valid. Do not ask the user what \`/k\` means. A bare \`/k\` must bootstrap Kernel orchestration immediately." "alias prompt requires bare /k bootstrap"
assert_contains "${ALIAS_FILE}" "do not read \`README.md\`, \`CODEX.md\`, \`AGENTS.md\`, \`docs/**\`, \`.fugue/**\`" "alias prompt forbids pre-bootstrap doc tours"
assert_contains "${ALIAS_FILE}" "The first useful output for a fresh \`/k\` start is the acknowledgement and live lane manifest, not a repository summary." "alias prompt prioritizes ack over repo summary"
assert_contains "${ALIAS_FILE}" "If the user explicitly asks for production verification, live workflow inspection is mandatory and overrides the default no-CI rule" "alias prompt overrides no-CI rule for production verification"
assert_contains "${ALIAS_FILE}" "during bootstrap and local analysis, do not request approval for exploratory convenience; exhaust local workspace evidence first" "alias prompt forbids exploratory approval requests during bootstrap"
assert_contains "${ALIAS_FILE}" "only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task" "alias prompt requires strict approval necessity"
assert_contains "${ALIAS_FILE}" "before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY" "alias prompt requires lane quiescence before approval prompts"
assert_contains "${ALIAS_FILE}" "do not surface an approval prompt while background Codex activity is still emitting output into the same terminal" "alias prompt forbids approval prompts during active background output"
assert_contains "${ALIAS_FILE}" "if lane quiescence cannot be achieved promptly, fail closed with a one-line \`quiescence_timeout\` status instead of surfacing the approval prompt" "alias prompt fail-closes when quiescence cannot be established"
assert_contains "${ALIAS_FILE}" "low-touch autonomous development" "alias prompt documents low-touch autonomy"

assert_contains "${CODEX_FILE}" "fresh Codex session started at the repository root and then \`/kernel\`" "CODEX documents fresh-session repo-root contract"
assert_contains "${CODEX_FILE}" "\`/k\` is a local one-word alias for \`/kernel\`" "CODEX documents /k alias"
assert_contains "${CODEX_FILE}" "supported local adapter path is \`kernel\` or \`codex-prompt-launch kernel\`" "CODEX documents local adapter path"
assert_contains "${CODEX_FILE}" "local alias prompt for one-word chat-box startup is \`.codex/prompts/k.md\`" "CODEX documents alias prompt path"
assert_contains "${CODEX_FILE}" "Treat \`codex-kernel-guard launch\` as the local execution authority" "CODEX documents guard authority"
assert_contains "${CODEX_FILE}" "Hot reload is not guaranteed." "CODEX documents restart requirement"
assert_contains "${CODEX_FILE}" "Bare \`/kernel\` inside the Codex chat UI is not a local SLO path" "CODEX documents bare slash boundary"
assert_contains "${CODEX_FILE}" "runtime smoke on a fresh session" "CODEX documents runtime smoke path"
assert_contains "${CODEX_FILE}" "local smoke or static checks are not sufficient to claim production PASS" "CODEX forbids local-only production PASS claim"
assert_contains "${CODEX_FILE}" "launch at least 6 active subagent lanes before the first acknowledgement" "CODEX documents subagent-first bootstrap"
assert_contains "${CODEX_FILE}" "minimum operating target is 6 or more concurrent lanes" "CODEX documents six-lane minimum"
assert_contains "${CODEX_FILE}" "must run a 3-round redesign loop by default" "CODEX documents redesign loop"
assert_contains "${CODEX_FILE}" "low-touch autonomous development" "CODEX documents low-touch autonomy"
assert_contains "${CODEX_FILE}" "must define requirements, constraints, acceptance criteria, failure modes, and stop conditions" "CODEX documents round-1 requirements definition"
assert_contains "${CODEX_FILE}" "If the user explicitly asks for production verification, the completion proof must define the live rerun or dispatch path" "CODEX documents production verification completion proof"
assert_contains "${CODEX_FILE}" "Codex + Claude + GLM" "CODEX documents baseline model set"
assert_contains "${CODEX_FILE}" "Codex, Claude, GLM, Copilot CLI, and Gemini CLI" "CODEX documents multi-agent core families"
assert_contains "${CODEX_FILE}" "Codex should act as the orchestrator and integration layer" "CODEX documents Codex orchestrator role"
assert_contains "${CODEX_FILE}" "Simulation lanes should prefer \`codex-spark\`" "CODEX documents codex-spark simulation preference"
assert_contains "${CODEX_FILE}" "Simulation validation is mandatory before implementation" "CODEX documents simulation validation gate"
assert_contains "${CODEX_FILE}" "\`codex-multi-agents\` is the default Codex fan-out substrate" "CODEX documents codex-multi-agents substrate"
assert_contains "${CODEX_FILE}" "\`claude-code-agent-teams\` is the default Claude delegation substrate" "CODEX documents claude-code-agent-teams substrate"
assert_contains "${CODEX_FILE}" "Claude and GLM must be treated as real peer lanes" "CODEX documents peer-lane delegation"
assert_contains "${CODEX_FILE}" "Do not treat subagents, \`codex-multi-agents\`, or \`claude-code-agent-teams\` alone as sufficient replacement" "CODEX forbids substrate-only replacement"
assert_contains "${CODEX_FILE}" "hand off into \`/vote\` as fast local implementation continuation" "CODEX documents /vote handoff"
assert_contains "${CODEX_FILE}" "must run cross-model quality review" "CODEX documents post-implementation QA"
assert_contains "${CODEX_FILE}" "For production verification tasks, do not stop at a patch, push, dispatch, partial log read, or status memo when concrete execution remains." "CODEX forbids early stop during production verification"
assert_contains "${CODEX_FILE}" "Lane manifest:" "CODEX documents lane manifest"
assert_contains "${CODEX_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "CODEX documents bootstrap target"
assert_contains "${CODEX_FILE}" "do not request approval for exploratory convenience" "CODEX documents approval necessity rule"
assert_contains "${CODEX_FILE}" "Only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required" "CODEX documents strict approval necessity"
assert_contains "${CODEX_FILE}" "When the user explicitly asks for production verification, live workflow inspection is part of the required completion path" "CODEX documents production verification no-CI override"
assert_contains "${CODEX_FILE}" "quiesce active lanes that can still write to the current TTY" "CODEX documents approval quiescence"
assert_contains "${CODEX_FILE}" "Do not surface approval prompts while background Codex activity is still emitting output into the same terminal." "CODEX documents approval prompt isolation"
assert_contains "${CODEX_FILE}" "fail closed with a one-line \`quiescence_timeout\` status" "CODEX documents approval fail-close"

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
assert_contains "${README_FILE}" "通常 3 ラウンドの再設計ループ" "README documents redesign loop"
assert_contains "${README_FILE}" "low-touch autonomous development" "README documents low-touch autonomy"
assert_contains "${README_FILE}" "要件・制約・受け入れ条件・失敗モード・停止条件" "README documents round-1 requirements definition"
assert_contains "${README_FILE}" "ユーザーが本番確認を明示した場合、その planning packet には live rerun / dispatch 経路" "README documents production verification completion proof"
assert_contains "${README_FILE}" "Codex + Claude + GLM" "README documents baseline model set"
assert_contains "${README_FILE}" "Codex / Claude / GLM / Copilot CLI / Gemini CLI" "README documents multi-agent core families"
assert_contains "${README_FILE}" "Codex は統合・分解・競合解消を担う orchestrator" "README documents Codex orchestrator role"
assert_contains "${README_FILE}" "\`codex-spark\` を第一候補" "README documents codex-spark simulation preference"
assert_contains "${README_FILE}" "simulation validation は実装前に必須の品質ゲート" "README documents simulation validation gate"
assert_contains "${README_FILE}" "\`codex-multi-agents\`" "README documents codex-multi-agents substrate"
assert_contains "${README_FILE}" "\`claude-code-agent-teams\`" "README documents claude-code-agent-teams substrate"
assert_contains "${README_FILE}" "Claude と GLM は \`/kernel\` の peer lane" "README documents peer-lane delegation"
assert_contains "${README_FILE}" "subagent / \`codex-multi-agents\` / \`claude-code-agent-teams\` だけで multi-model core を代替" "README forbids substrate-only replacement"
assert_contains "${README_FILE}" "\`/vote\` に hand off して実装" "README documents /vote handoff"
assert_contains "${README_FILE}" "異なる LLM モデルで品質レビュー" "README documents post-implementation QA"
assert_contains "${README_FILE}" "本番確認タスクでは、patch・push・dispatch・部分ログ確認で止めてはいけません。" "README forbids early stop during production verification"
assert_contains "${README_FILE}" "本番 PASS は local test / readiness だけでは主張できません。" "README forbids local-only production PASS claim"
assert_contains "${README_FILE}" "Lane manifest:" "README documents lane manifest"
assert_contains "${README_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "README documents bootstrap target"
assert_contains "${README_FILE}" "便宜的な探索のために approval を要求してはいけません" "README documents approval necessity rule"
assert_contains "${README_FILE}" "ユーザーが本番確認を明示した場合、live workflow / artifact inspection は完遂条件の一部" "README documents production verification no-CI override"
assert_contains "${README_FILE}" "approval は、ユーザーが明示的に求めた場合か" "README documents strict approval necessity"
assert_contains "${README_FILE}" "同じ TTY に書き続ける active lane は quiesce" "README documents approval quiescence"
assert_contains "${README_FILE}" "同じ terminal に出力中のまま approval prompt を表示してはいけません" "README documents approval prompt isolation"
assert_contains "${README_FILE}" "\`quiescence_timeout\`" "README documents approval fail-close"
assert_contains "${GATE_FILE}" "'.codex/prompts/k.md'" "gate watches /k alias prompt"

matrix_policy_payload="$("${ROOT_DIR}/scripts/lib/build-agent-matrix.sh" \
  --engine subscription \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode enhanced \
  --glm-subagent-mode paired \
  --allow-glm-in-subscription true \
  --wants-gemini true \
  --format json)"
if echo "${matrix_policy_payload}" | jq -e '
  ([.matrix.include[] | select(.provider == "gemini" or .provider == "xai")] | length) == 0
' >/dev/null 2>&1; then
  echo "[PASS] kernel topology suppresses metered lanes without reason" >&2
else
  echo "[FAIL] kernel topology unexpectedly allowed metered lanes without reason" >&2
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
  --metered-reason overflow \
  --format json)"
if echo "${matrix_metered_payload}" | jq -e '
  (.metered_reason == "overflow")
  and ([.matrix.include[] | select(.provider == "gemini" and .metered_reason == "overflow")] | length) == 1
' >/dev/null 2>&1; then
  echo "[PASS] kernel topology requires reason-tagged metered lanes" >&2
else
  echo "[FAIL] kernel topology did not preserve reason-tagged metered lane metadata" >&2
  failures=$((failures + 1))
fi

if [[ "${RUN_CODEX_KERNEL_SMOKE:-0}" == "1" ]]; then
  cleanup_stale_smoke_processes() {
    python3 - <<'PY'
import os
import signal
import subprocess

patterns = ("kernel-smoke-", "kernel-session-smoke-")
keepers = {os.getpid(), os.getppid()}
targets: list[int] = []

ps = subprocess.run(
    ["ps", "-axo", "pid=,command="],
    capture_output=True,
    text=True,
    check=True,
)

for raw_line in ps.stdout.splitlines():
    line = raw_line.strip()
    if not line:
        continue
    parts = line.split(None, 1)
    if len(parts) != 2:
        continue
    pid = int(parts[0])
    command = parts[1]
    if pid in keepers:
        continue
    if not any(pattern in command for pattern in patterns):
        continue
    if not any(token in command for token in ("codex-prompt-launch", "run_with_pty.py", "/codex ")):
        continue
    targets.append(pid)

for pid in targets:
    try:
        os.killpg(os.getpgid(pid), signal.SIGKILL)
    except ProcessLookupError:
        continue
    except OSError:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, OSError):
            continue
PY
  }

  run_codex_smoke() {
    local prompt_name="$1"
    local focus_text="$2"
    ROOT_DIR="${ROOT_DIR}" PROMPT_NAME="${prompt_name}" FOCUS_TEXT="${focus_text}" SMOKE_TIMEOUT_SEC="${smoke_timeout_sec}" python3 - <<'PY'
import os
import subprocess
import sys

root_dir = os.environ["ROOT_DIR"]
prompt_name = os.environ["PROMPT_NAME"]
focus_text = os.environ["FOCUS_TEXT"]
timeout_sec = int(os.environ["SMOKE_TIMEOUT_SEC"])
launcher = "/Users/masayuki/Dev/tools/codex-prompt-launcher/bin/codex-prompt-launch"
pty_runner = "/Users/masayuki/Dev/tools/codex-prompt-launcher/scripts/run_with_pty.py"
command = ["python3", pty_runner, "--cwd", root_dir, "--timeout-sec", str(timeout_sec), "--", launcher, prompt_name]
if focus_text:
    command.append(focus_text)

try:
    proc = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout_sec,
    )
except subprocess.TimeoutExpired as exc:
    output = exc.stdout or ""
    error = exc.stderr or ""
    if isinstance(output, bytes):
        output = output.decode("utf-8", errors="replace")
    if isinstance(error, bytes):
        error = error.decode("utf-8", errors="replace")
    sys.stdout.write(output)
    sys.stderr.write(error)
    sys.exit(124)

sys.stdout.write(proc.stdout)
sys.stderr.write(proc.stderr)
sys.exit(proc.returncode)
PY
  }

  audit_canary_timeout() {
    local prompt_name="$1"
    local marker="$2"
    ROOT_DIR="${ROOT_DIR}" PROMPT_NAME="${prompt_name}" MARKER="${marker}" PYTHONPATH="/Users/masayuki/Dev/tools/codex-kernel-guard/src${PYTHONPATH:+:${PYTHONPATH}}" python3 - <<'PY'
import json
import os
import sqlite3
from pathlib import Path
from codex_kernel_guard.session_watch import audit_session_jsonl_with_evidence

def collect_assistant_output(rollout_path: Path) -> str:
    messages: list[str] = []
    for raw_line in rollout_path.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            event = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if event.get("type") != "response_item":
            continue
        payload = event.get("payload") or {}
        if payload.get("type") != "message" or payload.get("role") != "assistant":
            continue
        for content in payload.get("content") or []:
            if not isinstance(content, dict):
                continue
            text = content.get("text")
            if isinstance(text, str) and text:
                messages.append(text)
    return "\n".join(messages)

def manifest_lane_count(text: str) -> int:
    in_manifest = False
    count = 0
    for raw_line in text.splitlines():
        line = raw_line.rstrip("\n")
        if line.strip() == "Lane manifest:":
            in_manifest = True
            continue
        if not in_manifest:
            continue
        if line.startswith("- "):
            count += 1
            continue
        if count > 0 and line.strip():
            break
    return count

root_dir = os.environ["ROOT_DIR"]
prompt_name = os.environ["PROMPT_NAME"]
marker = os.environ["MARKER"]
state_db = Path("/Users/masayuki/.codex/state_5.sqlite")
bootstrap_root = Path("/Users/masayuki/Dev/kernel-orchestration-tools/state/bootstrap-evidence")

conn = sqlite3.connect(state_db)
conn.row_factory = sqlite3.Row
row = conn.execute(
    """
    SELECT rollout_path, created_at
    FROM threads
    WHERE source IN ('cli', 'exec')
      AND cwd = ?
      AND (
        title LIKE ?
        OR first_user_message LIKE ?
      )
    ORDER BY created_at DESC
    LIMIT 1
    """,
    (root_dir, f"%{marker}%", f"%{marker}%"),
).fetchone()
if row is None:
    raise SystemExit(2)
rollout_path = Path(row["rollout_path"])
thread_created_at = int(row["created_at"])
code, _, _ = audit_session_jsonl_with_evidence(
    rollout_path,
    min_active_lanes=6,
    min_distinct_lane_families=2,
    required_phase_evidence=("plan", "simulate", "critique", "repair", "replan"),
)
if code != 0:
    raise SystemExit(3)
assistant_output = collect_assistant_output(rollout_path)
if (
    "Kernel orchestration is active for this session." not in assistant_output
    or "Bootstrap target: 6+ lanes (minimum 6)." not in assistant_output
    or "Lane manifest:" not in assistant_output
    or manifest_lane_count(assistant_output) < 6
    or f"Smoke result marker: {marker}" not in assistant_output
    or "errored" in assistant_output
):
    raise SystemExit(5)

evidence_ok = False
for path in sorted(bootstrap_root.glob(f"bootstrap-{prompt_name}-*"), key=lambda p: p.stat().st_mtime, reverse=True):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    prompt_root = str(payload.get("prompt_root") or "")
    prompt_name_value = str(payload.get("prompt_name") or "")
    if prompt_root != root_dir or prompt_name_value != prompt_name:
        continue
    created_at = str(payload.get("created_at") or "")
    if not created_at:
        continue
    try:
        evidence_ts = int(Path(path).stat().st_mtime)
    except OSError:
        continue
    if abs(evidence_ts - thread_created_at) > 600:
        continue
    providers = payload.get("providers") or []
    names = {
        str(item.get("provider") or "").strip().lower()
        for item in providers
        if isinstance(item, dict) and item.get("ok") is True
    }
    if {"claude", "glm"}.issubset(names):
        evidence_ok = True
        break
if not evidence_ok:
    raise SystemExit(4)
print("timeout-audit-pass")
PY
  }

  audit_canary_timeout_with_retry() {
    local prompt_name="$1"
    local marker="$2"
    local attempt=0
    while [[ "${attempt}" -lt 6 ]]; do
      if audit_canary_timeout "${prompt_name}" "${marker}" >/dev/null 2>&1; then
        return 0
      fi
      attempt=$((attempt + 1))
      sleep 5
    done
    return 1
  }

  run_smoke_check() {
    local prompt_name="$1"
    local label="$2"
    local attempt=0
    local smoke_output=""
    local smoke_rc=0
    local marker=""
    local can_try_timeout_audit=0

    while [[ "${attempt}" -lt 2 ]]; do
      marker="kernel-smoke-${prompt_name}-$$-$(date +%s)-${RANDOM}"
      set +e
      smoke_output="$(run_codex_smoke "${prompt_name}" "SMOKE_RESULT_MARKER=${marker}" 2>&1)"
      smoke_rc=$?
      set -e
      local lane_count=0
      lane_count="$(printf '%s\n' "${smoke_output}" | python3 - <<'PY'
import sys

in_manifest = False
count = 0
for raw_line in sys.stdin:
    line = raw_line.rstrip("\n")
    if line.strip() == "Lane manifest:":
        in_manifest = True
        continue
    if not in_manifest:
        continue
    if line.startswith("- "):
        count += 1
        continue
    if count > 0 and line.strip():
        break
print(count)
PY
)"
      local fresh_session_pass=0
      if grep -Fq 'preflight: PASS:' <<<"${smoke_output}" \
        && grep -Fq 'Kernel orchestration is active for this session.' <<<"${smoke_output}" \
        && grep -Fq 'Bootstrap target: 6+ lanes (minimum 6).' <<<"${smoke_output}" \
        && grep -Fq 'Lane manifest:' <<<"${smoke_output}" \
        && [[ "${lane_count}" -ge 6 ]] \
        && grep -Fq 'Kernel runtime canary: PASS' <<<"${smoke_output}" \
        && grep -Fq "Smoke result marker: ${marker}" <<<"${smoke_output}" \
        && ! grep -Fq 'errored' <<<"${smoke_output}" \
        && ! grep -Fq 'monitor: FAIL:' <<<"${smoke_output}" \
        && ! grep -Fq 'audit: FAIL:' <<<"${smoke_output}"; then
        fresh_session_pass=1
      fi
      if [[ "${fresh_session_pass}" -eq 1 ]]; then
        echo "[PASS] runtime smoke: ${label} canary passed in fresh session" >&2
        return 0
      fi
      can_try_timeout_audit=0
      if grep -Fq 'preflight: PASS:' <<<"${smoke_output}" \
        && grep -Fq 'Kernel runtime canary: PASS' <<<"${smoke_output}" \
        && grep -Fq "Smoke result marker: ${marker}" <<<"${smoke_output}"; then
        can_try_timeout_audit=1
      elif grep -Fq 'preflight: PASS:' <<<"${smoke_output}" && [[ "${smoke_rc}" -eq 124 ]]; then
        can_try_timeout_audit=1
      elif grep -Fq 'preflight: PASS:' <<<"${smoke_output}" \
        && [[ "${smoke_rc}" -ne 0 ]] \
        && ! grep -Fq 'monitor: FAIL:' <<<"${smoke_output}" \
        && ! grep -Fq 'audit: FAIL:' <<<"${smoke_output}"; then
        can_try_timeout_audit=1
      fi
      if [[ "${can_try_timeout_audit}" -eq 1 ]]; then
        if audit_canary_timeout_with_retry "${prompt_name}" "${marker}"; then
          echo "[PASS] runtime smoke: ${label} canary passed via timeout audit" >&2
          return 0
        fi
      fi
      attempt=$((attempt + 1))
    done

    if [[ "${smoke_rc}" -eq 124 ]]; then
      echo "[FAIL] runtime smoke: ${label} timed out after ${smoke_timeout_sec}s" >&2
    else
      echo "[FAIL] runtime smoke: ${label} canary failed" >&2
    fi
    printf '%s\n' "${smoke_output}" >&2
    failures=$((failures + 1))
  }

  cleanup_stale_smoke_processes
  run_smoke_check "kernel" "/kernel"
  run_smoke_check "k" "/k"
fi

if (( failures > 0 )); then
  echo "codex kernel prompt check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "codex kernel prompt check passed"
