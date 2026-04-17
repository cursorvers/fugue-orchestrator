# FUGUE Watchdog Waiting-Run Drill

## Purpose

Verify that `fugue-watchdog` treats old GitHub Actions `waiting` runs as a
control-plane health signal instead of silently collapsing query failures or
stuck queues to "healthy".

This drill is intentionally split into deterministic local simulation and
operator-attended live verification.

## Local Deterministic Drill

Run:

```bash
bash scripts/harness/run-watchdog-waiting-run-drill.sh \
  --waiting-run-count 1 \
  --waiting-run-age-minutes 61 \
  --waiting-run-oldest "drill-workflow/123"
```

Expected:

- `should_alert=true`
- `workflow-waiting` appears in the active or due reasons
- the generated message includes the simulated waiting run label

Suppression check:

```bash
bash scripts/harness/run-watchdog-waiting-run-drill.sh \
  --waiting-run-count 0 \
  --waiting-run-age-minutes 0
```

Expected:

- `should_alert=false`
- no `workflow-waiting` reason

## Live Operator Drill

Use this only when an operator intentionally wants to validate live GitHub
queue behavior. Do not create artificial workload during production incidents.

1. Confirm the current queue:

```bash
gh run list \
  --repo cursorvers/fugue-orchestrator \
  --status waiting \
  --limit 200 \
  --json databaseId,workflowName,status,createdAt,url
```

2. Trigger watchdog manually:

```bash
gh workflow run fugue-watchdog.yml --repo cursorvers/fugue-orchestrator --ref main
```

3. Confirm the `Detect waiting workflow runs` and `Decide whether to alert`
   steps. If no live waiting run is older than the threshold, this is a healthy
   no-alert result.

4. If a stale waiting run exists, confirm that the alert reason is
   `workflow-waiting` and that `FUGUE_WATCHDOG_ALERT_STATE` is updated only
   through the alert or recovery persistence paths.

## Safety Rules

- Do not print secret values.
- Do not cancel or rerun unrelated production jobs just to force a waiting run.
- Do not persist drill-only state unless the run is an actual watchdog alert.
- Treat query failure as unhealthy: the workflow must never turn a failed
  waiting-run query into an empty list.
