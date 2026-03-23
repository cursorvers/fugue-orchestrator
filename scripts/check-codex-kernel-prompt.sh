#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="${ROOT_DIR}/.codex/prompts/kernel.md"
ALIAS_FILE="${ROOT_DIR}/.codex/prompts/k.md"
CODEX_FILE="${ROOT_DIR}/CODEX.md"
README_FILE="${ROOT_DIR}/README.md"
GLOBAL_PROMPT_FILE="${HOME}/.codex/prompts/kernel.md"
GLOBAL_ALIAS_FILE="${HOME}/.codex/prompts/k.md"
GATE_FILE="${ROOT_DIR}/.github/workflows/fugue-orchestration-gate.yml"
KERNEL_CONCEPT_FILES=(
  "${PROMPT_FILE}"
  "${ALIAS_FILE}"
  "${CODEX_FILE}"
  "${ROOT_DIR}/docs/kernel-chatgpt-gpt-semi-auto-import.md"
  "${ROOT_DIR}/docs/kernel-codex-import-strategy.md"
  "${ROOT_DIR}/docs/kernel-context-governor.md"
  "${ROOT_DIR}/docs/kernel-happy-app-implementation-plan.md"
  "${ROOT_DIR}/docs/kernel-happy-app-single-front-architecture.md"
  "${ROOT_DIR}/docs/kernel-live-cutover-status-2026-03-06.md"
  "${ROOT_DIR}/docs/kernel-mini-mbp-ops-topology.md"
  "${ROOT_DIR}/docs/kernel-mobile-content-workflow.md"
  "${ROOT_DIR}/docs/kernel-peripheral-audit.md"
  "${ROOT_DIR}/docs/kernel-preimplementation-readiness.md"
  "${ROOT_DIR}/docs/kernel-recovery-runbook.md"
  "${ROOT_DIR}/docs/kernel-sovereign-adapter-contract.md"
  "${ROOT_DIR}/docs/kernel-structure.md"
  "${ROOT_DIR}/docs/kernel-tailscale-railway-integration-design.md"
)

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

assert_no_raw_fugue_concept() {
  local path="$1"
  if grep -nE '\bFUGUE\b' "${path}" >/dev/null; then
    echo "[FAIL] kernel concept separation: raw 'FUGUE' found in ${path}" >&2
    grep -nE '\bFUGUE\b' "${path}" >&2 || true
    failures=$((failures + 1))
  else
    echo "[PASS] kernel concept separation: ${path}" >&2
  fi
}

assert_file "${PROMPT_FILE}"
assert_file "${ALIAS_FILE}"
assert_file "${CODEX_FILE}"
assert_file "${README_FILE}"
assert_file "${GATE_FILE}"

if [[ -f "${GLOBAL_PROMPT_FILE}" ]]; then
  assert_contains "${GLOBAL_PROMPT_FILE}" "required kernel voices for this workspace are \`codex\`, \`glm\`, and one specialist from \`gemini-cli\`, \`cursor-cli\`, or \`copilot-cli\`" "global prompt defines kernel voice minimum"
  assert_contains "${GLOBAL_PROMPT_FILE}" "\`Claude\` is optional in Kernel and must not be treated as a bootstrap prerequisite" "global prompt excludes claude bootstrap requirement"
  assert_contains "${GLOBAL_PROMPT_FILE}" "\`BLOCKED\` is valid only when neither the normal shape nor the degraded-allowed shape can be established" "global prompt narrows blocked condition"
fi

if [[ -f "${GLOBAL_ALIAS_FILE}" ]]; then
  assert_contains "${GLOBAL_ALIAS_FILE}" "Treat \`/k\` as a local one-word alias for \`/kernel\`." "global alias prompt defines /k alias"
  assert_contains "${GLOBAL_ALIAS_FILE}" "\`Claude\` is optional in Kernel and must not be treated as a bootstrap prerequisite" "global alias prompt excludes claude bootstrap requirement"
fi

assert_contains "${PROMPT_FILE}" "maintain at least 6 materially distinct active lanes" "prompt requires >=6 active lanes"
assert_contains "${PROMPT_FILE}" "do not collapse, defer, or silently degrade to single-thread execution" "prompt forbids single-thread degradation"
assert_contains "${PROMPT_FILE}" "treat de-parallelization as a policy violation" "prompt marks de-parallelization as violation"
assert_contains "${PROMPT_FILE}" "launch at least 6 materially distinct subagents immediately before any substantive analysis" "prompt requires immediate subagent launch"
assert_contains "${PROMPT_FILE}" "bootstrap target is at least 6 concurrent lanes" "prompt requires six-lane minimum"
assert_contains "${PROMPT_FILE}" "required kernel voices for this workspace are \`codex\`, \`glm\`, and one specialist from \`gemini-cli\`, \`cursor-cli\`, or \`copilot-cli\`" "prompt defines kernel voice minimum"
assert_contains "${PROMPT_FILE}" "\`Claude\` is optional in Kernel and must not be treated as a bootstrap prerequisite" "prompt excludes claude bootstrap requirement"
assert_contains "${PROMPT_FILE}" "\`gemini-cli\`, \`cursor-cli\`, and \`copilot-cli\` as specialist lanes with free-tier or quota limits" "prompt defines specialist lanes"
assert_contains "${PROMPT_FILE}" "optional specialist selection is dynamic; choose the healthiest available specialist by quota and availability instead of a fixed provider order" "prompt defines dynamic optional specialist selection"
assert_contains "${PROMPT_FILE}" "treat \`copilot-cli\` free usage as scarce monthly budget and avoid autopilot by default" "prompt defines copilot scarcity rule"
assert_contains "${PROMPT_FILE}" "\`kgemini\`, \`kcursor\`, or \`kcopilot\`" "prompt defines wrapper-first optional lane usage"
assert_contains "${PROMPT_FILE}" "\`codex-kernel-guard budget-consume <provider> 1 <note>\`" "prompt defines optional lane atomic budget consume"
assert_contains "${PROMPT_FILE}" "route GLM execution through \`kglm\` whenever feasible" "prompt defines kglm-first glm execution"
assert_contains "${PROMPT_FILE}" "\`glm\` fails twice in the same run" "prompt defines glm degraded transition"
assert_contains "${PROMPT_FILE}" "\`glm\` is unavailable at bootstrap time" "prompt defines immediate degraded bootstrap fallback"
assert_contains "${PROMPT_FILE}" "valid three-voice shape cannot be established" "prompt fails closed on missing valid three-voice shape"
assert_contains "${PROMPT_FILE}" "\`BLOCKED\` is valid only when neither the normal shape nor the degraded-allowed shape can be established" "prompt narrows blocked condition"
assert_contains "${PROMPT_FILE}" "do not add helpers, abstractions, or features that the user did not ask for" "prompt forbids unrequested feature growth"
assert_contains "${PROMPT_FILE}" "do not treat a rule as implemented when it exists only in prompt text, comments, or docs" "prompt forbids doc-only rule completion"
assert_contains "${PROMPT_FILE}" "a Kernel rule is incomplete until it is enforced by launch/guard or runtime code, reflected in receipt/health evidence, and covered by a regression test" "prompt requires enforce-evidence-test completion"
assert_contains "${PROMPT_FILE}" "prefer the smallest concrete change that satisfies the request" "prompt requires smallest sufficient change"
assert_contains "${PROMPT_FILE}" "reject speculative redesign, side quests, and \"nice to have\" functionality" "prompt rejects speculative redesign"
assert_contains "${PROMPT_FILE}" "Complete a pre-implementation cycle before editing or irreversible actions" "prompt requires pre-implementation cycle"
assert_contains "${PROMPT_FILE}" "simulate or verify the plan with tests, dry-runs, static checks, or bounded command-level rehearsal" "prompt requires simulation before implementation"
assert_contains "${PROMPT_FILE}" "gpt-5.3-codex-spark" "prompt defines codex-spark simulation lane"
assert_contains "${PROMPT_FILE}" "treat requirement definition as critical work" "prompt requires requirements wall-bat"
assert_contains "${PROMPT_FILE}" "treat non-trivial requirement definition, planning, implementation, and review as Kernel work by default" "prompt requires kernel-first non-trivial work"
assert_contains "${PROMPT_FILE}" "do not label a plan as a Kernel plan unless the required diverse voices for that plan are actually active in the current run" "prompt forbids codex-only kernel plans"
assert_contains "${PROMPT_FILE}" "Front-load user interaction into requirement definition" "prompt front-loads clarification"
assert_contains "${PROMPT_FILE}" "planning diversity must explicitly account for \`glm\` and the specialist pool (\`gemini-cli\`, \`cursor-cli\`, \`copilot-cli\`)" "prompt requires planning diversity accounting"
assert_contains "${PROMPT_FILE}" "if uncertainty remains after context gathering, explicitly say that you do not have enough information instead of guessing" "prompt requires explicit uncertainty admission"
assert_contains "${PROMPT_FILE}" "for long or source-grounded inputs, extract direct quotes first and analyze only those quotes" "prompt requires quote-first analysis"
assert_contains "${PROMPT_FILE}" "before finalizing a claim-heavy answer, verify each claim against available quotes or sources and remove unsupported claims" "prompt requires unsupported-claim pruning"
assert_contains "${PROMPT_FILE}" "define a receipt strategy for unattended visibility before implementation starts" "prompt requires receipt strategy"
assert_contains "${PROMPT_FILE}" "Before the first acknowledgement, write a bootstrap receipt" "prompt requires bootstrap receipt"
assert_contains "${PROMPT_FILE}" "KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV" "prompt requires bootstrap active models evidence"
assert_contains "${PROMPT_FILE}" "KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT" "prompt requires bootstrap manifest lane evidence"
assert_contains "${PROMPT_FILE}" "KERNEL_BOOTSTRAP_AGENT_LABELS=true" "prompt requires bootstrap agent-label evidence"
assert_contains "${PROMPT_FILE}" "KERNEL_BOOTSTRAP_SUBAGENT_LABELS=true" "prompt requires bootstrap subagent-label evidence"
assert_contains "${PROMPT_FILE}" "Do not ask the user to confirm routine progress between planning and implementation." "prompt forbids routine confirmation pauses"
assert_contains "${PROMPT_FILE}" "Do not emit routine intermediate progress reports or midpoint summaries during execution." "prompt forbids routine intermediate reports"
assert_contains "${PROMPT_FILE}" "After requirements are frozen, report only when blocked, when external approval is required, when the user explicitly asks, or when final completion is reached." "prompt limits reporting to blockers or completion"
assert_contains "${PROMPT_FILE}" "Do not pause execution to summarize a partial milestone, sub-slice, or intermediate checkpoint while the active request is still in progress." "prompt forbids partial milestone pauses"
assert_contains "${PROMPT_FILE}" "Do not stop execution merely because one stage, track, or implementation slice finished while the broader frozen request remains incomplete." "prompt forbids stage-slice stops"
assert_contains "${PROMPT_FILE}" "Do not emit a completion-style summary until the active request is actually complete or truly blocked." "prompt forbids premature completion summaries"
assert_contains "${PROMPT_FILE}" "Active models: <main model>, <diversity model>, <diversity model> ..." "prompt requires active models line"
assert_contains "${PROMPT_FILE}" "Lane manifest:" "prompt requires lane manifest"
assert_contains "${PROMPT_FILE}" "currently active lanes, not planned lanes" "prompt forbids planned-lane manifest"
assert_contains "${PROMPT_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "prompt requires bootstrap target line"
assert_contains "${PROMPT_FILE}" "Do not claim multi-model orchestration if only Codex lanes are active." "prompt forbids codex-only success"
assert_contains "${PROMPT_FILE}" "Use \`gpt-5.3-codex-spark\` only for that dedicated simulation lane by default so simulation stays fast; keep other Codex-family subagents selected by role." "prompt limits codex-spark to simulation lane"
assert_contains "${PROMPT_FILE}" "name the provider for each lane and indicate whether it is \`codex\`, \`glm\`, or \`specialist\`" "prompt requires lane provider labels"
assert_contains "${PROMPT_FILE}" "explicitly identify the active agent and the concrete subagent label (\`subagent1\`, \`subagent2\`, ...) or \`none\` for every lane" "prompt requires numbered subagent labels"
assert_contains "${PROMPT_FILE}" "Do not count unlabeled, pending, failed, or merely planned lanes toward the manifest." "prompt excludes non-live lanes"
assert_contains "${PROMPT_FILE}" "\`Active models:\` must list only models with live evidence from the current run." "prompt limits active model line to live evidence"
assert_contains "${ALIAS_FILE}" "Treat \`/k\` as a local one-word alias for \`/kernel\`." "alias prompt identifies /k semantics"
assert_contains "${ALIAS_FILE}" "launch at least 6 materially distinct subagents immediately before any substantive analysis" "alias prompt requires immediate subagent launch"
assert_contains "${ALIAS_FILE}" "required kernel voices for this workspace are \`codex\`, \`glm\`, and one specialist from \`gemini-cli\`, \`cursor-cli\`, or \`copilot-cli\`" "alias prompt defines kernel voice minimum"
assert_contains "${ALIAS_FILE}" "\`Claude\` is optional in Kernel and must not be treated as a bootstrap prerequisite" "alias prompt excludes claude bootstrap requirement"
assert_contains "${ALIAS_FILE}" "\`gemini-cli\`, \`cursor-cli\`, and \`copilot-cli\` as specialist lanes with free-tier or quota limits" "alias prompt defines specialist lanes"
assert_contains "${ALIAS_FILE}" "optional specialist selection is dynamic; choose the healthiest available specialist by quota and availability instead of a fixed provider order" "alias prompt defines dynamic optional specialist selection"
assert_contains "${ALIAS_FILE}" "do not add helpers, abstractions, or features that the user did not ask for" "alias prompt forbids unrequested feature growth"
assert_contains "${ALIAS_FILE}" "do not treat a rule as implemented when it exists only in prompt text, comments, or docs" "alias prompt forbids doc-only rule completion"
assert_contains "${ALIAS_FILE}" "a Kernel rule is incomplete until it is enforced by launch/guard or runtime code, reflected in receipt/health evidence, and covered by a regression test" "alias prompt requires enforce-evidence-test completion"
assert_contains "${ALIAS_FILE}" "prefer the smallest concrete change that satisfies the request" "alias prompt requires smallest sufficient change"
assert_contains "${ALIAS_FILE}" "reject speculative redesign, side quests, and \"nice to have\" functionality" "alias prompt rejects speculative redesign"
assert_contains "${ALIAS_FILE}" "Complete a pre-implementation cycle before editing or irreversible actions" "alias prompt requires pre-implementation cycle"
assert_contains "${ALIAS_FILE}" "simulate or verify the plan with tests, dry-runs, static checks, or bounded command-level rehearsal" "alias prompt requires simulation before implementation"
assert_contains "${ALIAS_FILE}" "gpt-5.3-codex-spark" "alias prompt defines codex-spark simulation lane"
assert_contains "${ALIAS_FILE}" "treat requirement definition as critical work" "alias prompt requires requirements wall-bat"
assert_contains "${ALIAS_FILE}" "treat non-trivial requirement definition, planning, implementation, and review as Kernel work by default" "alias prompt requires kernel-first non-trivial work"
assert_contains "${ALIAS_FILE}" "do not label a plan as a Kernel plan unless the required diverse voices for that plan are actually active in the current run" "alias prompt forbids codex-only kernel plans"
assert_contains "${ALIAS_FILE}" "Front-load user interaction into requirement definition" "alias prompt front-loads clarification"
assert_contains "${ALIAS_FILE}" "planning diversity must explicitly account for \`glm\` and the specialist pool (\`gemini-cli\`, \`cursor-cli\`, \`copilot-cli\`)" "alias prompt requires planning diversity accounting"
assert_contains "${ALIAS_FILE}" "if uncertainty remains after context gathering, explicitly say that you do not have enough information instead of guessing" "alias prompt requires explicit uncertainty admission"
assert_contains "${ALIAS_FILE}" "for long or source-grounded inputs, extract direct quotes first and analyze only those quotes" "alias prompt requires quote-first analysis"
assert_contains "${ALIAS_FILE}" "before finalizing a claim-heavy answer, verify each claim against available quotes or sources and remove unsupported claims" "alias prompt requires unsupported-claim pruning"
assert_contains "${ALIAS_FILE}" "Do not ask the user to confirm routine progress between planning and implementation." "alias prompt forbids routine confirmation pauses"
assert_contains "${ALIAS_FILE}" "Do not emit routine intermediate progress reports or midpoint summaries during execution." "alias prompt forbids routine intermediate reports"
assert_contains "${ALIAS_FILE}" "After requirements are frozen, report only when blocked, when external approval is required, when the user explicitly asks, or when final completion is reached." "alias prompt limits reporting to blockers or completion"
assert_contains "${ALIAS_FILE}" "Do not pause execution to summarize a partial milestone, sub-slice, or intermediate checkpoint while the active request is still in progress." "alias prompt forbids partial milestone pauses"
assert_contains "${ALIAS_FILE}" "Do not stop execution merely because one stage, track, or implementation slice finished while the broader frozen request remains incomplete." "alias prompt forbids stage-slice stops"
assert_contains "${ALIAS_FILE}" "Do not emit a completion-style summary until the active request is actually complete or truly blocked." "alias prompt forbids premature completion summaries"
assert_contains "${ALIAS_FILE}" "\`kgemini\`, \`kcursor\`, or \`kcopilot\`" "alias prompt defines wrapper-first optional lane usage"
assert_contains "${ALIAS_FILE}" "\`codex-kernel-guard budget-consume <provider> 1 <note>\`" "alias prompt defines optional lane atomic budget consume"
assert_contains "${ALIAS_FILE}" "route GLM execution through \`kglm\` whenever feasible" "alias prompt defines kglm-first glm execution"
assert_contains "${ALIAS_FILE}" "\`glm\` fails twice in the same run" "alias prompt defines glm degraded transition"
assert_contains "${ALIAS_FILE}" "\`glm\` is unavailable at bootstrap time" "alias prompt defines immediate degraded bootstrap fallback"
assert_contains "${ALIAS_FILE}" "\`BLOCKED\` is valid only when neither the normal shape nor the degraded-allowed shape can be established" "alias prompt narrows blocked condition"
assert_contains "${ALIAS_FILE}" "define a receipt strategy for unattended visibility before implementation starts" "alias prompt requires receipt strategy"
assert_contains "${ALIAS_FILE}" "Before the first acknowledgement, write a bootstrap receipt" "alias prompt requires bootstrap receipt"
assert_contains "${ALIAS_FILE}" "KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV" "alias prompt requires bootstrap active models evidence"
assert_contains "${ALIAS_FILE}" "KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT" "alias prompt requires bootstrap manifest lane evidence"
assert_contains "${ALIAS_FILE}" "KERNEL_BOOTSTRAP_AGENT_LABELS=true" "alias prompt requires bootstrap agent-label evidence"
assert_contains "${ALIAS_FILE}" "KERNEL_BOOTSTRAP_SUBAGENT_LABELS=true" "alias prompt requires bootstrap subagent-label evidence"
assert_contains "${ALIAS_FILE}" "Active models: <main model>, <diversity model>, <diversity model> ..." "alias prompt requires active models line"
assert_contains "${ALIAS_FILE}" "Lane manifest:" "alias prompt requires lane manifest"
assert_contains "${ALIAS_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "alias prompt requires bootstrap target line"
assert_contains "${ALIAS_FILE}" "Use \`gpt-5.3-codex-spark\` only for that dedicated simulation lane by default so simulation stays fast; keep other Codex-family subagents selected by role." "alias prompt limits codex-spark to simulation lane"
assert_contains "${ALIAS_FILE}" "explicitly identify the active agent and the concrete subagent label (\`subagent1\`, \`subagent2\`, ...) or \`none\` for every lane" "alias prompt requires numbered subagent labels"
assert_contains "${ALIAS_FILE}" "Do not count unlabeled, pending, failed, or merely planned lanes toward the manifest." "alias prompt excludes non-live lanes"
assert_contains "${ALIAS_FILE}" "\`Active models:\` must list only models with live evidence from the current run." "alias prompt limits active model line to live evidence"

assert_contains "${CODEX_FILE}" "fresh Codex session started at the repository root and then \`/kernel\`" "CODEX documents fresh-session repo-root contract"
assert_contains "${CODEX_FILE}" "\`/k\` is a local one-word alias for \`/kernel\`" "CODEX documents /k alias"
assert_contains "${CODEX_FILE}" "supported local adapter path is \`kernel\` or \`codex-prompt-launch kernel\`" "CODEX documents local adapter path"
assert_contains "${CODEX_FILE}" "local alias prompt for one-word chat-box startup is \`.codex/prompts/k.md\`" "CODEX documents alias prompt path"
assert_contains "${CODEX_FILE}" "Treat \`codex-kernel-guard launch\` as the local execution authority" "CODEX documents guard authority"
assert_contains "${CODEX_FILE}" "Hot reload is not guaranteed." "CODEX documents restart requirement"
assert_contains "${CODEX_FILE}" "Bare \`/kernel\` inside the Codex chat UI is not a local SLO path" "CODEX documents bare slash boundary"
assert_contains "${CODEX_FILE}" "runtime smoke on a fresh session" "CODEX documents runtime smoke path"
assert_contains "${CODEX_FILE}" "CI static enforcement: the orchestration gate workflow runs \`bash scripts/check-codex-kernel-prompt.sh\`" "CODEX documents kernel prompt CI enforcement"
assert_contains "${CODEX_FILE}" "launch at least 6 active subagent lanes before the first acknowledgement" "CODEX documents subagent-first bootstrap"
assert_contains "${CODEX_FILE}" "minimum operating target is 6 or more concurrent lanes" "CODEX documents six-lane minimum"
assert_contains "${CODEX_FILE}" "normal minimum healthy Kernel shape for this workspace is \`codex\` + \`glm\` + one specialist" "CODEX documents normal kernel minimum"
assert_contains "${CODEX_FILE}" "\`Claude\` is not part of the Kernel minimum and must never be treated as a bootstrap prerequisite." "CODEX excludes claude bootstrap requirement"
assert_contains "${CODEX_FILE}" "\`gemini-cli\`, \`cursor-cli\`, and \`copilot-cli\` are specialist voices with free-tier or quota limits" "CODEX documents specialist voices"
assert_contains "${CODEX_FILE}" "Optional specialist selection is dynamic. Choose the healthiest available specialist by quota and availability instead of a fixed provider order." "CODEX documents dynamic optional specialist selection"
assert_contains "${CODEX_FILE}" "\`kernel-optional-lane-exec.sh auto ...\` uses that dynamic selection instead of hard-coded provider priority." "CODEX documents auto specialist execution"
assert_contains "${CODEX_FILE}" "Optional specialist usage should normally go through \`kgemini\`, \`kcursor\`, or \`kcopilot\`; manual accounting must use \`codex-kernel-guard budget-consume\`." "CODEX documents optional lane budget workflow"
assert_contains "${CODEX_FILE}" "GLM execution should normally go through \`kglm\`" "CODEX documents kglm workflow"
assert_contains "${CODEX_FILE}" "\`glm\` fails twice in the same run, Kernel may enter \`degraded-allowed\`" "CODEX documents glm degraded mode"
assert_contains "${CODEX_FILE}" "\`glm\` is unavailable at bootstrap time, Kernel should use the degraded shape immediately" "CODEX documents immediate degraded bootstrap fallback"
assert_contains "${CODEX_FILE}" "Do not add features, helpers, abstractions, or convenience layers unless they are indispensable" "CODEX forbids unrequested feature growth"
assert_contains "${CODEX_FILE}" "Do not count a rule as implemented when it only exists in prompt text, comments, or docs." "CODEX forbids doc-only rule completion"
assert_contains "${CODEX_FILE}" "A Kernel rule is complete only when it has harness/runtime enforcement, receipt or health evidence, and a regression test." "CODEX requires enforce-evidence-test completion"
assert_contains "${CODEX_FILE}" "Prefer the smallest concrete change that preserves three-voice diversity" "CODEX requires smallest sufficient change"
assert_contains "${CODEX_FILE}" "Reject speculative redesign, side quests, and \"nice to have\" expansion" "CODEX rejects speculative redesign"
assert_contains "${CODEX_FILE}" "Before implementation, run a pre-implementation cycle: gather context, make a plan, simulate or verify it, critique it, then revise it." "CODEX requires pre-implementation cycle"
assert_contains "${CODEX_FILE}" "gpt-5.3-codex-spark" "CODEX defines codex-spark simulation lane"
assert_contains "${CODEX_FILE}" "Requirement definition is the first control point." "CODEX requires requirements wall-bat"
assert_contains "${CODEX_FILE}" "non-trivial requirement definition, planning, implementation, and review are Kernel work by default" "CODEX requires kernel-first non-trivial work"
assert_contains "${CODEX_FILE}" "Do not call a plan a Kernel plan unless the required diverse voices for that plan are actually active in the current run." "CODEX forbids codex-only kernel plans"
assert_contains "${CODEX_FILE}" "Use that early wall-bat to prevent goal drift" "CODEX prevents goal drift"
assert_contains "${CODEX_FILE}" "Planning must explicitly account for \`glm\` and the specialist pool (\`gemini-cli\`, \`cursor-cli\`, \`copilot-cli\`) before implementation starts." "CODEX requires planning diversity accounting"
assert_contains "${CODEX_FILE}" "Use \`gpt-5.3-codex-spark\` only for that dedicated simulation lane by default so simulation stays fast; keep other Codex-family subagents selected by role." "CODEX limits codex-spark to simulation lane"
assert_contains "${CODEX_FILE}" "Default to one-pass delivery" "CODEX requires one-pass delivery"
assert_contains "${CODEX_FILE}" "Only pause for the user when the next step is destructive, requires external credentials or approval, or is materially ambiguous." "CODEX limits pauses to hard blockers"
assert_contains "${CODEX_FILE}" "Do not emit routine intermediate progress reports or midpoint summaries during execution." "CODEX forbids routine intermediate reports"
assert_contains "${CODEX_FILE}" "After requirements are frozen, report only when blocked, when external approval is required, when the user explicitly asks, or when final completion is reached." "CODEX limits reporting to blockers or completion"
assert_contains "${CODEX_FILE}" "Do not stop to summarize partial milestones, sub-slices, or intermediate checkpoints while the active request is still in progress." "CODEX forbids partial milestone pauses"
assert_contains "${CODEX_FILE}" "Do not stop execution merely because one stage, track, or implementation slice finished while the broader frozen request remains incomplete." "CODEX forbids stage-slice stops"
assert_contains "${CODEX_FILE}" "Do not emit a completion-style summary until the active request is actually complete or truly blocked." "CODEX forbids premature completion summaries"
assert_contains "${CODEX_FILE}" "shared run evidence for all active lanes" "CODEX reuses auth evidence across lanes"
assert_contains "${CODEX_FILE}" "one bounded non-interactive recovery sweep per run" "CODEX bounds auth recovery retries per run"
assert_contains "${CODEX_FILE}" "\`launch\` may fail closed on readiness, but \`doctor\`, \`doctor --run\`, and \`recover-run\` are the non-interactive-first surfaces" "CODEX distinguishes launch from doctor/recover auth behavior"
assert_contains "${CODEX_FILE}" "Kernel runs should emit and maintain a bootstrap receipt" "CODEX requires bootstrap receipt"
assert_contains "${CODEX_FILE}" "live manifest evidence" "CODEX requires manifest evidence in bootstrap receipt"
assert_contains "${CODEX_FILE}" "The first valid acknowledgement must include an \`Active models:\` line" "CODEX requires active models line"
assert_contains "${CODEX_FILE}" "Lane manifest:" "CODEX documents lane manifest"
assert_contains "${CODEX_FILE}" "Each manifest lane must name its provider, active agent, and concrete subagent label (\`subagent1\`, \`subagent2\`, ...) or \`none\`." "CODEX requires numbered subagent labels"
assert_contains "${CODEX_FILE}" "Unlabeled, pending, failed, or merely planned lanes do not count toward the Kernel minimum." "CODEX excludes non-live lanes"
assert_contains "${CODEX_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "CODEX documents bootstrap target"
assert_contains "${CODEX_FILE}" "\`k\` is the human-facing shortcut surface: \`k\`, \`k all\`, \`k latest\`, \`k run-id\`, \`k new <purpose> [focus]\`, \`k adopt <session:window> [purpose]\`, \`k <run_id>\`, \`k show <run_id>\`, \`k open [run_id]\`, \`k phase <phase>\`, \`k done <summary...>\`." "CODEX documents k shortcut surface"
assert_contains "${CODEX_FILE}" "\`codex-kernel-guard adopt-run <session:window> [purpose]\` is the path for turning a live unmanaged tmux window into a Kernel run and moving it into a dedicated heavy-profile session." "CODEX documents adopt-run path"
assert_contains "${CODEX_FILE}" "On \`Mac mini\`, bare \`codex\` inside the Kernel repo should default to \`kernel\` and only offer raw Codex as an explicit opt-out" "CODEX documents codex auto-route with explicit opt-out"
assert_contains "${CODEX_FILE}" "On \`Mac mini\`, \`kernel\` with no arguments should reopen the latest active run by default; if no active run exists, it should fall through to guarded launch." "CODEX documents kernel auto-open default"
assert_contains "${CODEX_FILE}" "Kernel startup adapters should keep the initial Codex-visible bootstrap text minimal." "CODEX requires minimal startup bootstrap text"
assert_contains "${CODEX_FILE}" "Prefer a short pointer to \`.codex/prompts/kernel.md\` plus run metadata over inlining the full Kernel prompt into the first visible Codex message." "CODEX forbids full prompt inline at startup"
assert_contains "${CODEX_FILE}" "\`1 tmux session = 1 Kernel run = 1 Codex thread\` is the Kernel handoff contract." "CODEX documents codex-thread handoff contract"
assert_contains "${CODEX_FILE}" "\`recover-run\` must recreate the heavy tmux session and relaunch the run-dedicated Codex thread in the \`main\` window." "CODEX documents thread relaunch on recovery"
assert_contains "${CODEX_FILE}" "\`purpose\` is fixed per run; if it drifts materially, create a new run instead of mutating the existing handoff identity." "CODEX documents purpose fixity"
assert_contains "${CODEX_FILE}" "Kernel should auto-record only at milestone boundaries by default: \`plan\`, \`implement\`, \`verify\`, and \`run-complete\`." "CODEX requires milestone-only auto recording"
assert_contains "${CODEX_FILE}" "Autosave should stay coarse-grained. Do not save on every tiny edit, file write, or partial thought." "CODEX requires coarse-grained autosave"
assert_contains "${CODEX_FILE}" "bash scripts/lib/kernel-milestone-record.sh checkpoint \"<summary>\"" "CODEX documents checkpoint save command"
assert_contains "${CODEX_FILE}" "Phase completion and run completion must refresh local save state, not just remote backup metadata." "CODEX requires local save refresh on completion"
assert_contains "${CODEX_FILE}" "always run \`codex-kernel-guard run-complete --summary <text>\`" "CODEX requires completion save"

assert_contains "${README_FILE}" "repo root で新規に開いた Codex セッションから \`/kernel\`" "README documents repo-root contract"
assert_contains "${README_FILE}" "chat 欄から 1語で起動したい場合の local alias は \`/k\`" "README documents /k alias"
assert_contains "${README_FILE}" "ローカルでの推奨実行経路は \`kernel\` または \`codex-prompt-launch kernel\`" "README documents launcher adapter path"
assert_contains "${README_FILE}" "1語 alias の prompt は [\`.codex/prompts/k.md\`]" "README documents alias prompt path"
assert_contains "${README_FILE}" "ローカル実行契約の authority は shell wrapper ではなく \`codex-kernel-guard launch\`" "README documents guard authority"
assert_contains "${README_FILE}" "hot reload は保証しません" "README documents hot reload limitation"
assert_contains "${README_FILE}" "bare \`/kernel\` は Codex chat UI の upstream 実装に依存" "README documents bare slash boundary"
assert_contains "${README_FILE}" "RUN_CODEX_KERNEL_SMOKE=1 bash tests/test-codex-kernel-prompt.sh" "README documents smoke command"
assert_contains "${README_FILE}" "非自明な要件定義 / 計画 / 実装 / レビューを Kernel work として扱い、plain Codex-only work に落とさない" "README documents kernel-first non-trivial work"
assert_contains "${README_FILE}" "最低 6 本の active lane" "README documents minimum active lanes"
assert_contains "${README_FILE}" "6 列以上の並列を最低形" "README documents six-lane minimum"
assert_contains "${README_FILE}" "normal minimum shape は \`codex\` + \`glm\` + \`specialist\`" "README documents normal minimum shape"
assert_contains "${README_FILE}" "\`gemini-cli\` / \`cursor-cli\` / \`copilot-cli\` は free-tier or quota-limited な specialist 候補" "README documents optional quota-limited specialists"
assert_contains "${README_FILE}" "normal minimum shape では specialist 1本が必須。1本も確保できない場合は fail-closed" "README documents fail-closed specialist requirement"
assert_contains "${README_FILE}" "optional specialist は固定優先順を持たず、quota と可用性が最も健全なものを動的に選ぶ" "README documents dynamic optional specialist selection"
assert_contains "${README_FILE}" "\`kernel-optional-lane-exec.sh auto ...\` はその動的選択を使う" "README documents auto specialist execution"
assert_contains "${README_FILE}" "optional specialist は通常 \`kgemini\` / \`kcursor\` / \`kcopilot\` 経由で使い、手動計上は \`codex-kernel-guard budget-consume\` を使う" "README documents atomic optional lane usage"
assert_contains "${README_FILE}" "GLM は通常 \`kglm\` 経由で実行し" "README documents kglm usage"
assert_contains "${README_FILE}" "\`gpt-5.3-codex-spark\`" "README documents codex-spark simulation lane"
assert_contains "${README_FILE}" "計画段階では \`glm\` と specialist pool（\`gemini-cli\` / \`cursor-cli\` / \`copilot-cli\`）を明示的に織り込む" "README documents planning diversity accounting"
assert_contains "${README_FILE}" "dedicated な 1 列だけを \`gpt-5.3-codex-spark\` で走らせる" "README limits codex-spark to dedicated simulation lane"
assert_contains "${README_FILE}" "他の Codex-family subagent は役割別に選び、全部を \`gpt-5.3-codex-spark\` に固定しない" "README keeps non-simulation subagents role-based"
assert_contains "${README_FILE}" "要件凍結後は routine な中間報告を出さず、\`BLOCKED\` / 外部承認待ち / 明示要求 / 最終完了 の時だけ報告する" "README forbids routine intermediate reports"
assert_contains "${README_FILE}" "進行中の依頼に対して、部分マイルストーンや途中スライスの総括で処理を止めない" "README forbids partial milestone pauses"
assert_contains "${README_FILE}" "1つの stage / track / 実装スライスが終わっただけでは止まらず、凍結済みの依頼全体が終わるまで続ける" "README forbids stage-slice stops"
assert_contains "${README_FILE}" "完了調の総括は、その依頼が本当に完了した時か、真に blocked の時だけにする" "README forbids premature completion summaries"
assert_contains "${README_FILE}" "bootstrap receipt を書き" "README documents bootstrap receipt usage"
assert_contains "${README_FILE}" "live manifest evidence" "README documents manifest evidence in receipt"
assert_contains "${README_FILE}" "\`purpose\` は run ごとに固定し、目的が変わるなら新しい run を切る" "README documents purpose fixity"
assert_contains "${README_FILE}" "Kernel の自動記録は既定で節目だけに寄せる。" "README documents milestone-only auto recording"
assert_contains "${README_FILE}" "自動 save は coarse-grained に保ち、細かな編集や partial thought ごとに打たない" "README documents coarse-grained autosave"
assert_contains "${README_FILE}" "bash scripts/lib/kernel-milestone-record.sh checkpoint \"<summary>\"" "README documents checkpoint save command"
assert_contains "${README_FILE}" "phase 完了と run 完了では remote backup だけでなく local save state も更新する" "README requires local save refresh on completion"
assert_contains "${README_FILE}" "タスク完了と判断したら必ず \`codex-kernel-guard run-complete --summary <text>\` を実行して completion を保存し、durable mirror まで通す" "README requires completion save"
assert_contains "${README_FILE}" "\`Active models:\` 行で、その run で実際に稼働している model だけを明示する" "README documents active models line"
assert_contains "${README_FILE}" "\`glm\` が同一 run で2回失敗したら \`degraded-allowed\` に入り" "README documents glm degraded mode"
assert_contains "${README_FILE}" "Lane manifest:" "README documents lane manifest"
assert_contains "${README_FILE}" "各 lane は provider に加えて agent と \`subagent1\` / \`subagent2\` / ... / \`none\` を明示する" "README documents numbered subagent labels"
assert_contains "${README_FILE}" "planned / pending / failed lane は数えない" "README excludes non-live lanes"
assert_contains "${README_FILE}" "Bootstrap target: 6+ lanes (minimum 6)." "README documents bootstrap target"
assert_contains "${README_FILE}" "\`k\` は人間向けの短縮入口で、\`k\`, \`k all\`, \`k latest\`, \`k run-id\`, \`k new <purpose> [focus]\`, \`k adopt <session:window> [purpose]\`, \`k <run_id>\`, \`k show <run_id>\`, \`k open [run_id]\`, \`k phase <phase>\`, \`k done <summary...>\` を使う" "README documents k shortcut surface"
assert_contains "${README_FILE}" "\`codex-kernel-guard adopt-run <session:window> [purpose]\` は unmanaged な live tmux window を Kernel run に昇格し、専用 heavy-profile session へ移す" "README documents adopt-run path"
assert_contains "${README_FILE}" "\`Mac mini\` では repo 内で bare \`codex\` を打った時の既定を \`kernel\` とし、raw Codex は明示的な opt-out に限る。" "README documents codex auto-route with explicit opt-out"
assert_contains "${README_FILE}" "\`Mac mini\` では \`kernel\` を引数なしで打つと最新の active run を開き、active run が無ければ通常の guarded launch に落ちる" "README documents kernel auto-open default"
assert_contains "${README_FILE}" "Kernel 起動アダプタは、Codex の初回表示に出る bootstrap 文面を最小限に保つ" "README requires minimal startup bootstrap text"
assert_contains "${README_FILE}" "初回表示では full prompt を inline せず、\`.codex/prompts/kernel.md\` への短い参照と run metadata を優先する" "README forbids full prompt inline at startup"
assert_contains "${README_FILE}" "\`1 tmux session = 1 Kernel run = 1 Codex thread\` を Kernel handoff 契約にする" "README documents codex-thread handoff contract"
assert_contains "${README_FILE}" "\`recover-run\` は再生成した \`main\` window で、その run 専用の Codex thread を立ち上げる" "README documents thread relaunch on recovery"
assert_contains "${GATE_FILE}" "bash scripts/check-codex-kernel-prompt.sh" "orchestration gate runs kernel prompt static contract"
assert_contains "${GATE_FILE}" "'.codex/prompts/k.md'" "gate watches /k alias prompt"

for concept_file in "${KERNEL_CONCEPT_FILES[@]}"; do
  assert_file "${concept_file}"
  assert_no_raw_fugue_concept "${concept_file}"
done

if [[ "${RUN_CODEX_KERNEL_SMOKE:-0}" == "1" ]]; then
  run_smoke_check() {
    local command_text="$1"
    local label="$2"
    local smoke_output=""
    local lane_manifest_count=0

    smoke_output="$(codex exec -C "${ROOT_DIR}" "${command_text}" 2>&1 || true)"
    lane_manifest_count="$(printf '%s\n' "${smoke_output}" | grep -Ec '^- .+: .+ - .+ \[provider:[^]]+\] \[agent:[^]]+\] \[subagent:(subagent[0-9]+|none)\]$' || true)"
    if grep -Eq 'Kernel orchestration is active (in|for) this session\.' <<<"${smoke_output}" \
      && grep -Fq 'Bootstrap target: 6+ lanes (minimum 6).' <<<"${smoke_output}" \
      && grep -Eq '^Active models: .+, .+, .+' <<<"${smoke_output}" \
      && grep -Fq 'Lane manifest:' <<<"${smoke_output}" \
      && [[ "${lane_manifest_count}" -ge 6 ]]; then
      echo "[PASS] runtime smoke: ${label} acknowledged in fresh session" >&2
    else
      echo "[FAIL] runtime smoke: ${label} acknowledgement missing" >&2
      printf '%s\n' "${smoke_output}" >&2
      failures=$((failures + 1))
    fi
  }

  run_smoke_check "/kernel" "/kernel"
  run_smoke_check "/k" "/k"
fi

if (( failures > 0 )); then
  echo "codex kernel prompt check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "codex kernel prompt check passed"
