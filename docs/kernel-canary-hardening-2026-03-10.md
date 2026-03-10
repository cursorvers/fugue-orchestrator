# Kernel Canary Hardening 2026-03-10

## Scope

This record captures the March 10, 2026 hardening pass for Kernel orchestration canary execution, router input validation, and production verification.

## Fixed

1. `scripts/harness/run-canary.sh`
   - correlated `workflow_dispatch` runs more safely instead of trusting the first unseen run id
   - held canary pass/close until the correlated workflow run reached terminal state
   - treated `failure`, `cancelled`, and `timed_out` workflow conclusions as canary failures
   - kept canary pass/fail comments shell-safe without backticks

2. `.github/workflows/fugue-task-router.yml`
   - rejected malformed `issue_number` inputs with `skip_reason=invalid-issue-number`
   - stopped collaborator permission probes when no trust subject was present
   - kept untrusted multiline outputs on randomized delimiters

3. `.github/workflows/fugue-tutti-router.yml`
   - rejected malformed `issue_number` inputs with `skip_reason=invalid-issue-number`
   - avoided label retry / runner probe paths when the issue number input was invalid
   - kept untrusted multiline outputs on randomized delimiters

4. `.github/workflows/fugue-tutti-caller.yml`
   - added workflow run naming for dispatch observability

## Regression Coverage

- `tests/test-kernel-canary-plan.sh`
- `tests/test-run-canary-progress-wait.sh`
- `tests/test-run-canary-run-failure.sh`
- `tests/test-router-invalid-issue-number.sh`
- `tests/test-task-router-start-signal.sh`
- `tests/test-kernel-recovery-console.sh`
- `tests/test-resolve-orchestration-context.sh`

## Production Verification

- Old orphaned canary issue `#472` was cleaned up after a newer verified run superseded it.
- Live production canary issue `#473` completed successfully.
- Correlated workflow run: `22900710070`
- Final canary state: `CLOSED` with stable labels plus `completed`

## Residual Note

GitHub Actions API exposure for run naming remains weaker than ideal. The current correlation path relies on dispatch timing, actor, branch, and unseen-run filtering when explicit run-name metadata is not surfaced by the API response.
