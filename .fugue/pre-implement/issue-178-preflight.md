## Cycle 1
### 1. Plan
- Map the fugue-codex-implement workflow to confirm the "Run parallel preflight nodes" step is executed before the main Codex CLI run and that it produces the mandated research/plan/critic artifacts.
- Focus on the control flow within that step to understand how each parallel node reports success/fallback artifacts and whether the job signals completion via the `parallel_preflight_*` outputs.
### 2. Parallel Simulation
- Emulated a parallel run purely by tracing `Run parallel preflight nodes`: it spawns detached worktrees for `research`, `plan`, and `critic`, feeds each a tailored instruction, runs `codex exec --full-auto`, and copies the resulting markdown (or fallback) into `.fugue/pre-implement` while logging exit codes.
- Verified that a failure still writes a fallback artifact describing the missing node, so even a degraded run satisfies the output contract.
### 3. Critical Review
- Noted that the step only proceeds when `PREFLIGHT_PARALLEL_ENABLED` resolves to `true`; otherwise, it emits fallback content and flags the main run to produce deeper work.
- Guarded against silent failures by confirming that `parallel_failures` increments if a node returns nonzero, ensuring a summary.log and flag for tertiary review.
### 4. Problem Fix
- Since no execution environment is available, the fix consists of documenting the fallback behavior so future reviewers know why artifacts might contain a stub in `Run parallel preflight nodes`.
- Logged that the `.fugue/pre-implement/issue-178-{research,plan,critic}.md` artifacts remain untouched by other steps, matching the contracts described in the step's output block.
### 5. Replan
- Next cycle will validate how the prepare job derives `context_budget_*` floors so that the parallel preflight step can rely on consistent context budgets and the forking of Codex models.
#### Candidate A
- Trust the `workflow-risk-policy.sh` defaults and focus on workflow-level verification, since the script already enforces floors and outputs the guard flags to the Codex CLI step.
#### Candidate B
- Rework the script to expose the same logic through documentation artifacts so the run can self-report context budgets alongside the parallel node logs.
#### Failure Modes
- Mis-reading the guard could lead to assuming the budgets are unchanged, even though the script enforces higher floors and writes `context_budget_guard_applied=true`.
#### Rollback Check
- No code was touched; rolling back would simply mean removing this descriptive analysis if, for some reason, the workflow is reconfigured.

## Cycle 2
### 1. Plan
- Dive into `scripts/lib/workflow-risk-policy.sh` to follow how `context_budget_initial`, `context_budget_max`, and the guard floors are calculated, paying special attention to the guard reasons and the link to the Codex CLI's plan.
- Identify how the initial/maximum budgets depend on `risk_tier` and whether the guard can raise any of them to meet the configured floors.
### 2. Parallel Simulation
- Simulated the guard's behavior by stepping through the calculations: default budgets (6/12 for medium risk) get compared against floors defined by `FUGUE_CONTEXT_BUDGET_MIN_*`, and any deficit raises the values while marking `context_budget_guard_applied=true` and capturing reasons like `raised-initial-floor` or `raised-span-floor`.
- Noted that the guard emits both the finalized budgets and the floor values into the workflow outputs so the Codex CLI run can include the correct context limits.
### 3. Critical Review
- The guard could inadvertently over-constrain Codex if the floors are higher than expected, so verifying that the output logs contain both the adjusted budgets and the guard reasons is vital for confirmation.
- Checked that the script ensures `context_budget_max >= context_budget_initial + context_budget_floor_span`, preventing a compressed span even if inputs attempted to tighten it.
### 4. Problem Fix
- Documented how the guard work prevents over-compression and how to interpret the guard flags in future runs, so reviewers know what to look for in the workflow logs.
- Highlighted that obeying the floors requires no workflow change; it's data captured and fed to the Codex CLI.
### 5. Replan
- For the last cycle, examine how the Codex CLI step consumes these guard outputs and ensures the preflight messages, artifacts, and task ledger exist before running the full implementation loop.
#### Candidate A
- Treat the Codex CLI run as the single source of truth for enforcing the protocol and ensure its log includes the verification of the parallel artifacts and the guard outputs.
#### Candidate B
- Cross-check the workflow outputs (`context_budget_guard_applied`, `context_budget_guard_reasons`, artifact paths) with the README or another doc to ensure transparency.
#### Failure Modes
- If the outputs are miswired, the Codex CLI might claim compliance while the artifacts are missing, so the guard must fail fast via the `missing mandatory preflight artifact` check.
#### Rollback Check
- Reverting to a previous commit leaves the script intact; only the documentation has been updated, so simply discarding this reasoning would undo the verification narrative.

## Cycle 3
### 1. Plan
- Confirm that the Codex CLI step (with the instruction block we just reviewed) enforces the preflight cycles, implementation dialogue rounds, task ledger structure, and lessons updates before allowing the job to proceed.
- Outline the expected artifacts and verify that the `todo` and `lessons` files meet their contracts.
### 2. Parallel Simulation
- Walked through the Codex CLI run: it writes `/tmp/codex-output.log`, checks for `.fugue/pre-implement/issue-178-preflight.md`, `.fugue/implement/issue-178-implementation-loop.md`, `.fugue/pre-implement/issue-178-todo.md`, and `.fugue/pre-implement/lessons.md`, and enforces the heading order along with guard flags from prepare.
- Confirmed that missing artifacts trigger explicit log messages, aligning with the acceptance criteria that the workflow must report the parallel nodes and context guard steps.
### 3. Critical Review
- The CLI also requires at least one checkbox in the todo file and recorded verification evidence for each preflight cycle, so any plan must embed that before `codex exec` completes.
- Missing `## Round N` or `### Implementer Proposal` headings now fail the guard, meaning our artifacts must follow the given templates exactly.
### 4. Problem Fix
- Captured this enforcement in the artifacts we are creating so the next workflow run will pass the guard.
- Noted that verifying the workflow success entails showing the transcripts (artifact presence, guard reasons) and the final run status (success/failure) in the `Run Codex CLI` logs.
### 5. Replan
- With the artifacts laid out, we can now draft the implementation dialogue loops and todo updates to satisfy the workflow's preflight/unblock requirements.
#### Candidate A
- Keep the artifacts lean and descriptive, matching the expected headings and referencing actual workflow steps so a reviewer can trace the verification path.
#### Candidate B
- Create more verbose logs and cross-reference them with manual tests to prove the guard is live in GitHub Actions.
#### Failure Modes
- Typos in headings or missing checkbox entries cause the CLI step to fail before actual work can begin.
#### Rollback Check
- No code changes exist; deleting these artifacts would simply revert to an unverified readme state.
