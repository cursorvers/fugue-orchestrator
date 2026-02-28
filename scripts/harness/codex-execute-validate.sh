#!/usr/bin/env bash
set -euo pipefail

# codex-execute-validate.sh — Execute Codex implementation and validate output.
#
# Runs Codex CLI with refinement cycles, validates output, creates PR,
# and posts implementation summary comment.
#
# Required env vars: OPENAI_API_KEY, GH_TOKEN, ISSUE_NUMBER,
#   ORCHESTRATION_PROFILE, REFINEMENT_CYCLES, IMPLEMENTATION_DIALOGUE_ROUNDS,
#   TARGET_REPO, and many more (see env: block in codex-implement execute step).
#
# Usage: bash scripts/harness/codex-execute-validate.sh

: > /tmp/codex-output.log

orchestration_profile="$(echo "${ORCHESTRATION_PROFILE:-codex-full}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${orchestration_profile}" != "codex-full" && "${orchestration_profile}" != "claude-light" ]]; then
  orchestration_profile="codex-full"
fi
cycles_raw="$(echo "${REFINEMENT_CYCLES:-3}" | tr -cd '0-9')"
if [[ -z "${cycles_raw}" ]]; then
  cycles_raw="3"
fi
if [[ "${orchestration_profile}" == "claude-light" ]]; then
  if (( cycles_raw < 1 )); then
    cycles_raw=1
  elif (( cycles_raw > 3 )); then
    cycles_raw=3
  fi
else
  if (( cycles_raw < 3 )); then
    cycles_raw=3
  elif (( cycles_raw > 5 )); then
    cycles_raw=5
  fi
fi
preflight_floor="$(echo "${PREFLIGHT_CYCLES_FLOOR:-1}" | tr -cd '0-9')"
if [[ -z "${preflight_floor}" ]]; then
  preflight_floor="1"
fi
if (( cycles_raw < preflight_floor )); then
  cycles_raw="${preflight_floor}"
fi
cycles="${cycles_raw}"
dialogue_rounds_raw="$(echo "${IMPLEMENTATION_DIALOGUE_ROUNDS:-2}" | tr -cd '0-9')"
if [[ -z "${dialogue_rounds_raw}" ]]; then
  dialogue_rounds_raw="2"
fi
if (( dialogue_rounds_raw < 1 )); then
  dialogue_rounds_raw=1
elif (( dialogue_rounds_raw > 5 )); then
  dialogue_rounds_raw=5
fi
dialogue_floor="$(echo "${IMPLEMENTATION_DIALOGUE_ROUNDS_FLOOR:-1}" | tr -cd '0-9')"
if [[ -z "${dialogue_floor}" ]]; then
  dialogue_floor="1"
fi
if (( dialogue_rounds_raw < dialogue_floor )); then
  dialogue_rounds_raw="${dialogue_floor}"
fi
dialogue_rounds="${dialogue_rounds_raw}"
risk_tier="$(echo "${RISK_TIER:-medium}" | tr '[:upper:]' '[:lower:]')"
if [[ "${risk_tier}" != "low" && "${risk_tier}" != "medium" && "${risk_tier}" != "high" ]]; then
  risk_tier="medium"
fi
lessons_required="$(echo "${LESSONS_REQUIRED:-false}" | tr '[:upper:]' '[:lower:]')"
if [[ "${lessons_required}" != "true" ]]; then
  lessons_required="false"
fi
correction_signal="$(echo "${CORRECTION_SIGNAL:-false}" | tr '[:upper:]' '[:lower:]')"
if [[ "${correction_signal}" != "true" ]]; then
  correction_signal="false"
fi
preflight_report=".fugue/pre-implement/issue-${ISSUE_NUMBER}-preflight.md"
implementation_report=".fugue/implement/issue-${ISSUE_NUMBER}-implementation-loop.md"
todo_report=".fugue/pre-implement/issue-${ISSUE_NUMBER}-todo.md"
lessons_report=".fugue/pre-implement/lessons.md"
research_report="${RESEARCH_REPORT_PATH:-.fugue/pre-implement/issue-${ISSUE_NUMBER}-research.md}"
plan_report="${PLAN_REPORT_PATH:-.fugue/pre-implement/issue-${ISSUE_NUMBER}-plan.md}"
critic_report="${CRITIC_REPORT_PATH:-.fugue/pre-implement/issue-${ISSUE_NUMBER}-critic.md}"
title_text="$(printf '%s\n' "${ISSUE_TITLE}" | tr '[:upper:]' '[:lower:]')"
goal_text="$(printf '%s\n' "${ISSUE_BODY}" | awk '
  BEGIN { capture=0 }
  /^###[[:space:]]*Goal[[:space:]]*$/ { capture=1; next }
  capture && /^###[[:space:]]/ { exit }
  capture && NF { print; exit }
' | tr '[:upper:]' '[:lower:]')"
task_signal_text="$(printf '%s\n%s\n' "${title_text}" "${goal_text}")"
is_large_refactor="false"
if [[ "${LARGE_REFACTOR_LABEL:-false}" == "true" ]]; then
  is_large_refactor="true"
elif echo "${task_signal_text}" | grep -Eqi '(大規模|全面|全体|リファクタ|refactor|migration|rewrite|アーキテクチャ刷新)'; then
  is_large_refactor="true"
fi

# Build instruction from issue
INSTRUCTION="## Task: ${ISSUE_TITLE}

${ISSUE_BODY}

## Mandatory pre-implementation protocol (${orchestration_profile})
- Before touching implementation, run this loop exactly ${cycles} times.
- Each cycle MUST include these five steps in order:
  1. Plan
  2. Parallel Simulation
  3. Critical Review
  4. Problem Fix
  5. Replan
- Record every cycle in ${preflight_report} using this exact section format:
  - ## Cycle N
  - ### 1. Plan
  - ### 2. Parallel Simulation
  - ### 3. Critical Review
  - ### 4. Problem Fix
  - ### 5. Replan
- Parallel Simulation and Critical Review are mandatory gates and cannot be skipped.
- If this is a large refactor/rewrite/migration task (detected=${is_large_refactor}), every cycle MUST include:
  - #### Candidate A
  - #### Candidate B
  - #### Failure Modes
  - #### Rollback Check
- After all preflight cycles complete, proceed to implementation-phase collaboration.
- If a cycle reveals a blocking issue, resolve it before moving to the next cycle.

## Mandatory implementation collaboration protocol
- During implementation, run this dialogue loop exactly ${dialogue_rounds} rounds.
- Treat this as team collaboration with distinct roles:
  - Implementer: proposes concrete code changes and file-level edits.
  - Critic: challenges regressions, security gaps, and test insufficiency.
  - Integrator: resolves disagreements and decides the merged patch direction.
- Record all rounds in ${implementation_report} using this exact format:
  - ## Round N
  - ### Implementer Proposal
  - ### Critic Challenge
  - ### Integrator Decision
  - ### Applied Change
  - ### Verification
- Apply only integrator-approved changes for each round.
- Final code must reflect the latest integrator decisions.

## Shared task management + self-improvement protocol
- Use this policy boundary:
  - MUST: preflight loops + implementation dialogue + verification evidence.
  - SHOULD: update lessons when correction signals/postmortem are present.
  - MAY: use extra subagent fan-out only for unresolved uncertainty.
- Parallel preflight seed artifacts already exist and MUST be refined (do not delete):
  - ${research_report}
  - ${plan_report}
  - ${critic_report}
- Risk tier for this issue: ${risk_tier} (score=${RISK_SCORE:-0}, reasons=${RISK_REASONS:-none}).
- Context budget guidance: initial sources <= ${CONTEXT_BUDGET_INITIAL:-6}, expand only when blocked up to ${CONTEXT_BUDGET_MAX:-12}.
- Context over-compression guard: applied=${CONTEXT_BUDGET_GUARD_APPLIED:-false}, reasons=${CONTEXT_BUDGET_GUARD_REASONS:-none}, floors=${CONTEXT_BUDGET_FLOOR_INITIAL:-6}/${CONTEXT_BUDGET_FLOOR_MAX:-12}/span${CONTEXT_BUDGET_FLOOR_SPAN:-6}.
- Keep checkable execution items in ${todo_report}.
- ${todo_report} MUST contain these headings:
  - ## Plan
  - ## Checklist
  - ## Progress
  - ## Review
- Checklist items must be markdown checkboxes and updated during execution.
- When correction signals or postmortem findings exist (required=${lessons_required}, correction_signal=${correction_signal}), append durable prevention rules to ${lessons_report}.
- If lessons are required for this issue, add a section header exactly: ## Issue #${ISSUE_NUMBER}
- Ensure ${lessons_report} exists (create a minimal header when lessons are not required in this run).
- ${lessons_report} entries should capture:
  - Mistake pattern
  - Preventive rule
  - Trigger signal
- Before finalizing, include concrete verification evidence (tests, logs, or behavioral diff).

## Rules
- Implement the changes described above
- Follow existing code style and patterns
- Do NOT modify unrelated files
- Ensure code compiles/passes lint
- Add tests if test infrastructure exists
- Keep all preflight reasoning concise and actionable"

# Write instruction to temp file to avoid shell escaping issues
echo "${INSTRUCTION}" > /tmp/codex-instruction.md

# Run Codex non-interactively in full-auto mode.
EXIT_CODE=0
codex exec \
  --model "${CODEX_MODEL}" \
  --full-auto \
  "$(cat /tmp/codex-instruction.md)" \
  2>&1 | tee /tmp/codex-output.log || EXIT_CODE=$?

echo "preflight_report_path=${preflight_report}" >> "${GITHUB_OUTPUT}"
echo "implementation_report_path=${implementation_report}" >> "${GITHUB_OUTPUT}"
echo "todo_report_path=${todo_report}" >> "${GITHUB_OUTPUT}"
echo "lessons_report_path=${lessons_report}" >> "${GITHUB_OUTPUT}"
echo "research_report_path=${research_report}" >> "${GITHUB_OUTPUT}"
echo "plan_report_path=${plan_report}" >> "${GITHUB_OUTPUT}"
echo "critic_report_path=${critic_report}" >> "${GITHUB_OUTPUT}"

# Enforce research/plan artifacts from parallel preflight stage.
for report in "${research_report}" "${plan_report}" "${critic_report}"; do
  if [[ ! -f "${report}" ]]; then
    echo "Missing mandatory preflight artifact: ${report}" | tee -a /tmp/codex-output.log
    EXIT_CODE=1
  fi
done

# Enforce the default refinement protocol before implementation is accepted.
if [[ ! -f "${preflight_report}" ]]; then
  echo "Missing mandatory preflight report: ${preflight_report}" | tee -a /tmp/codex-output.log
  EXIT_CODE=1
else
  for i in $(seq 1 "${cycles}"); do
    if ! grep -q "^## Cycle ${i}$" "${preflight_report}"; then
      echo "Missing section: ## Cycle ${i}" | tee -a /tmp/codex-output.log
      EXIT_CODE=1
      continue
    fi
    block="$(awk -v n="${i}" '
      $0 == "## Cycle " n {on=1; next}
      on && /^## Cycle [0-9]+$/ {exit}
      on {print}
    ' "${preflight_report}")"
    for heading in \
      "### 1. Plan" \
      "### 2. Parallel Simulation" \
      "### 3. Critical Review" \
      "### 4. Problem Fix" \
      "### 5. Replan"; do
      if ! printf '%s\n' "${block}" | grep -q "^${heading}$"; then
        echo "Cycle ${i} missing heading: ${heading}" | tee -a /tmp/codex-output.log
        EXIT_CODE=1
      fi
    done
    if [[ "${is_large_refactor}" == "true" ]]; then
      for heading in \
        "#### Candidate A" \
        "#### Candidate B" \
        "#### Failure Modes" \
        "#### Rollback Check"; do
        if ! printf '%s\n' "${block}" | grep -q "^${heading}$"; then
          echo "Cycle ${i} missing large-refactor section: ${heading}" | tee -a /tmp/codex-output.log
          EXIT_CODE=1
        fi
      done
    fi
  done
fi

# Enforce implementation-phase dialogue loop report.
if [[ ! -f "${implementation_report}" ]]; then
  echo "Missing mandatory implementation collaboration report: ${implementation_report}" | tee -a /tmp/codex-output.log
  EXIT_CODE=1
else
  for i in $(seq 1 "${dialogue_rounds}"); do
    if ! grep -q "^## Round ${i}$" "${implementation_report}"; then
      echo "Missing section: ## Round ${i}" | tee -a /tmp/codex-output.log
      EXIT_CODE=1
      continue
    fi
    block="$(awk -v n="${i}" '
      $0 == "## Round " n {on=1; next}
      on && /^## Round [0-9]+$/ {exit}
      on {print}
    ' "${implementation_report}")"
    for heading in \
      "### Implementer Proposal" \
      "### Critic Challenge" \
      "### Integrator Decision" \
      "### Applied Change" \
      "### Verification"; do
      if ! printf '%s\n' "${block}" | grep -q "^${heading}$"; then
        echo "Round ${i} missing heading: ${heading}" | tee -a /tmp/codex-output.log
        EXIT_CODE=1
      fi
    done
  done
fi

# Enforce shared task tracking artifact.
if [[ ! -f "${todo_report}" ]]; then
  echo "Missing mandatory task ledger: ${todo_report}" | tee -a /tmp/codex-output.log
  EXIT_CODE=1
else
  for heading in "## Plan" "## Checklist" "## Progress" "## Review"; do
    if ! grep -q "^${heading}$" "${todo_report}"; then
      echo "Task ledger missing heading: ${heading}" | tee -a /tmp/codex-output.log
      EXIT_CODE=1
    fi
  done
  if ! grep -Eq '^[[:space:]]*-[[:space:]]\[[ xX]\][[:space:]]+' "${todo_report}"; then
    echo "Task ledger has no markdown checkbox items: ${todo_report}" | tee -a /tmp/codex-output.log
    EXIT_CODE=1
  fi
fi

# Lessons are strict only when correction/postmortem signals are present.
if [[ ! -f "${lessons_report}" ]]; then
  if [[ "${lessons_required}" == "true" ]]; then
    echo "Missing required lessons artifact: ${lessons_report}" | tee -a /tmp/codex-output.log
    EXIT_CODE=1
  else
    mkdir -p "$(dirname "${lessons_report}")"
    {
      echo "# Lessons Ledger"
      echo
      echo "_Autocreated because lessons update was optional for this run._"
    } > "${lessons_report}"
  fi
fi
if [[ "${lessons_required}" == "true" ]]; then
  if ! grep -Eq "^##[[:space:]]+Issue[[:space:]]+#${ISSUE_NUMBER}([[:space:]].*)?$" "${lessons_report}"; then
    echo "Lessons required but missing issue-specific section beginning with: ## Issue #${ISSUE_NUMBER}" | tee -a /tmp/codex-output.log
    EXIT_CODE=1
  fi
fi

echo "exit_code=${EXIT_CODE}" >> "${GITHUB_OUTPUT}"

# Check if any files were changed (including untracked files).
# `git diff` does not detect newly-created (untracked) files, which can
# cause us to incorrectly skip commit/PR creation.
if [[ -z "$(git status --porcelain)" ]]; then
  echo "no_changes=true" >> "${GITHUB_OUTPUT}"
else
  echo "no_changes=false" >> "${GITHUB_OUTPUT}"
fi
