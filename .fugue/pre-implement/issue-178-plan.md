# Issue #178 Plan Artifact

## Objective
Verify the prod (fugue-codex-implement) workflow triggers the parallel preflight nodes for research/plan/critic and that the over-compression guard keeps context artifacts intact.

## Sequence
1. **Trigger workflow** – Re-run or re-dispatch the existing `fugue-codex-implement` workflow for Issue #178 so that preflight runs start with current config.
2. **Observe parallel nodes** – Watch the workflow logs and/or job graph to confirm `Run parallel preflight nodes` step executes and emits artifacts under the `research/`, `plan/`, and `critic/` directories.
3. **Verify context guard** – Check that generated artifacts are not over-compressed (e.g., context budgets respected) by comparing artifact sizes/contents or confirming guard log lines inside the same workflow run.
4. **Capture outcome** – Note whether the workflow completes (success/failure) and capture relevant log snippets or job statuses for the preflight nodes and guard stage.

## Rollback Plan
- If the workflow execution is misconfigured or fails to start, revert to the last known-good workflow YAML (no change expected) and reapply the validated configuration; cancel the current run and restart.
- If artifacts fail to appear, review runner logs to ensure the artifact publishing step ran; rerun the workflow once the underlying issue is understood.

## Verification Checkpoints
- Workflow start: confirm `fugue-codex-implement` run is queued/started via the GitHub UI or API.
- Parallel nodes: confirm logs show `research`, `plan`, and `critic` nodes running concurrently and that the `Run parallel preflight nodes` step exists and succeeds/fails as expected.
- Artifacts: assert `research/`, `plan/`, `critic/` directories appear in the artifact manifest and contain non-empty files.
- Completion: verify workflow conclusion (success or failure) is recorded with timestamp; document the final status.
