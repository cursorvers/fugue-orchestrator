## Round 1
### Implementer Proposal
- Capture that the "Run parallel preflight nodes" step spawns the `research`, `plan`, and `critic` lanes, writes artifact paths into the workflow outputs, and logs summary diagnostics.
- Document that the artifacts are required before Codex CLI runs the refinement cycles so the tail-end checks succeed.
### Critic Challenge
- Ensure the proposal explicitly states the filenames and that fallback behavior writes a placeholder file if a node fails; otherwise, the CLI reports "Missing mandatory preflight artifact".
- Question whether the artifacts are woven into the final implementation report or are separate; the workflow only mandates the markdown files exist with their headings.
### Integrator Decision
- Keep the documentation as-is but emphasize the exact artifact names and the `parallel_preflight_enabled=true` flag; this keeps the contract accessible to reviewers.
### Applied Change
- Added reference content to the preflight file describing the node behavior and fallback mechanics, matching the workflow steps.
### Verification
- Verified `.github/workflows/fugue-codex-implement.yml` lines 240-360 define the parallel nodes, create worktrees, run `codex exec`, and copy artifacts to `.fugue/pre-implement/issue-178-{research,plan,critic}.md` before issuing result logs.

## Round 2
### Implementer Proposal
- Explain how the guard in `scripts/lib/workflow-risk-policy.sh` computes context budget floors, emits `context_budget_guard_*` outputs, and forces `context_budget_max >= context_budget_initial + context_budget_floor_span` so the CLI doesn't over-compress.
- Tie those outputs to the Codex CLI step, which passes them as environment variables and checks for their presence before execution.
### Critic Challenge
- Confirm that the guard actually writes the adjusted budgets back to the workflow outputs and that the Codex CLI consumes them instead of the defaults; otherwise, the job could proceed with stale values.
- Highlight that the CLI logs include the guard reason string, making it easy to spot when the floors are enforced.
### Integrator Decision
- Affirm that linking the script's output to the CLI environment is sufficient, and no code changes are necessary beyond documenting the values and reasoning.
### Applied Change
- Added the lessons and todo artifacts showing we checked the guard logic and referenced the outputs, so the enforcement path is transparent.
### Verification
- Confirmed `scripts/lib/workflow-risk-policy.sh` lines 218-279 raise budgets when below floors, set `context_budget_guard_applied` true, and emit the updated values, which the workflow then makes available to the Codex CLI.
