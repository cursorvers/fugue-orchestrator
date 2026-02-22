# Shared Workflow Playbook Smoke Test

FUGUEのCodex/Claude共通プレイブックを素早く再確認するための簡易手順をまとめています。各ステップは両オーケストレーターの期待を含み、最小運用でplaybook成果物の整合性を確かめます。

## Steps

### 1. Confirm skill manifest sync and intent parity
- Check that both Codex and Claude environments have synchronized useful skills (`config/skills/fugue-openclaw-baseline.tsv`) copied before execution, and document any missing entries.
- The smoke test is invalid if one orchestrator cannot reach the curated skill set; log the mismatch and correct the sync script before proceeding.

### 2. Verify pre-implement artifacts
- Ensure `.fugue/pre-implement/issue-<N>-todo.md` and `.fugue/pre-implement/lessons.md` are present, referenced, and updated per the playbook regardless of whether Codex or Claude is the main orchestrator.
- Confirm the todo checklist mirrors the targeted steps and that lessons capture prevention rules when changes are made.

### 3. Assert signal lane coverage
- Run a quick mental walkthrough to confirm the playbook will add the correct `codex-main-orchestrator` or `claude-main-orchestrator` lane and any Claude assist lanes (Opus/Sonnet) depending on resolved providers.
- Record the expected lane set and reason about how the shared playbook keeps Codex/Claude treatment consistent.

### 4. Exercise implementation dialogue expectations
- Outline the planned Implementer → Critic → Integrator dialogue for the upcoming change, ensuring both orchestrators know which artifacts (plans, simulations, lessons) they must supply.
- Validate that the new docs or workflows reference the required checkpoints so each orchestrator can confirm compliance.

### 5. Capture verification evidence
- Note the smoke test inputs (commands, doc references) and the observations that show the shared playbook guided the change; include this text near the final deliverables.
- Keep a short record pointing to the README link so reviewers can re-trigger the smoke test as needed.

## Verification
- Manually check that each heading level ascends cleanly (`#`, `##`, `###`) and that the five steps remain descriptive but concise.
- After editing, run or simulate a markdown linter to ensure no skipped headings or improper list nesting occurred.
