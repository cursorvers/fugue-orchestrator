# Kernel Production Canary Incident: 2026-03-09

## Summary

- Incident class: production canary and Tutti dispatches timed out before integrated review.
- First clear failing main canary after the trust hardening changes: run `22834730756`.
- Affected canary issues from that run: `#418` and `#419`.
- User-visible symptom: canary ended with `reason=timeout-no-integrated-review`.

## Impact

- Production `main` canary validation was not trustworthy while the defect was present.
- `Claude agent teams` proof runs could show `enabled(...)` on the issue thread but still fail before the actual agent lanes started.
- Stale canary issues accumulated because failures were left open for inspection.

## Primary Root Cause

The reusable workflow job `tutti / prepare` in
[.github/workflows/fugue-tutti-router.yml](/Users/masayuki/Dev/tmp/fugue-kernel-finalize/.github/workflows/fugue-tutti-router.yml)
invoked the repo-owned script `scripts/lib/canary-trust-policy.sh` before running `actions/checkout`.

On hosted runners, reusable workflow jobs do not automatically have repository files available in the workspace. That meant the trust step failed with:

- `bash: scripts/lib/canary-trust-policy.sh: No such file or directory`

Because that failure happened inside a command substitution feeding `eval`, the next lines then tried to export variables that had never been initialized.

## Secondary Cause

The same trust step exported:

- `permission=${permission}`
- `trusted=${trusted}`
- `trust_reason=${trust_reason}`

without fallback-safe initialization. That produced a second failure signature:

- `permission: unbound variable`

This obscured the real root cause and made the incident look like a trust-policy logic failure instead of a missing-checkout failure.

## Why This Escaped Earlier Checks

1. Local verification covered the trust policy script itself, but not the hosted-runner filesystem semantics of the reusable workflow job.
2. Static regression coverage checked that the router delegated trust to `canary-trust-policy.sh`, but did not check that checkout happened before script invocation.
3. The earlier canary fixes solved trust routing and ownership wiring, which allowed execution to progress far enough to expose this next failure class.

## Detection Evidence

- Failing production canary:
  - `22834730756`
- Failing mainframe runs spawned by that canary:
  - `22834734073`
  - `22834733416`
- Failing signature in `tutti / prepare`:
  - missing `scripts/lib/canary-trust-policy.sh`
  - then `permission: unbound variable`

## Corrective Changes

### Runtime fix

Merged via PR `#421`, merge commit `f7b5cd4d12c0911e833cfe4733b93208fcf9ea4f`.

Changes:

- added `actions/checkout@v4` before `Check author trust` in `tutti / prepare`
- initialized fallback-safe trust outputs before policy eval:
  - `permission`
  - `trusted`
  - `trust_reason`

### Recovery validation

- main gate success: `22834961262`
- production canary success: `22834967428`

### Live Claude teams proof

Proof issue `#416` was rerun after the fix. In run `22834970888`, these Claude lanes completed successfully:

- `claude-main-orchestrator`
- `claude-opus-assist`
- `claude-sonnet6-assist`
- `claude-sonnet4-assist`

This established that `Claude agent teams` were not merely configured; they actually executed on GitHub-hosted infrastructure after the fix.

## Preventive Actions Added

### 1. Checkout-order static audit

Merged via PR `#428`, merge commit `7481bd25b8537a11a1cbb80aa3cf5c9d61befbc6`.

Added:

- [tests/test-workflow-checkout-order.sh](/Users/masayuki/Dev/tmp/fugue-kernel-finalize/tests/test-workflow-checkout-order.sh)

This test fails CI if any workflow step invokes repo-owned scripts before a checkout step in the same job.

### 2. Specific regression guard for the trust step

The canary wiring test now checks that `tutti / prepare` checks out the repository before invoking `canary-trust-policy.sh`.

### 3. Fallback-safe trust outputs

The trust step now initializes output variables before policy eval, which prevents future `unbound variable` masking if the policy script or workspace state breaks again.

## Operational Cleanup Performed

- stale historical canary issues were closed after successful production validation
- proof issue `#416` was closed after Claude teams execution was confirmed
- open `"[canary"` issues after cleanup: `0`

## Residual Risk

- Other workflow steps that use `eval "$(...)"` can still benefit from explicit fallback-safe initialization if their policy scripts are ever missing or malformed.
- The new checkout-order audit prevents the exact hosted-runner file-availability failure class, but not every possible policy-script failure.

## Standing Rule

For GitHub-hosted and reusable workflows in Kernel orchestration:

1. Any step that executes repo-owned scripts must run after `actions/checkout`.
2. Any step that exports values produced by `eval "$(...)"` must initialize fallback-safe defaults before eval.
3. Hosted-runner production fixes must be validated with a live main canary, not only local tests.
