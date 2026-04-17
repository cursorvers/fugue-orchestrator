# FUGUE / Kernel Version-Up Completion Record (2026-04-17)

## Summary

The 2026-04 FUGUE / Kernel version-up reached the current target.

- Target achievement: 100%
- Remaining slices for the current scope: 0
- Production status: green
- MBP status: green
- macmini status: green
- Secret contract status: MBP / macmini shared-secret simulation passed

This record covers the completion verification after PR #702 and PR #705.

## Scope Verified

- `FUGUE` and `Kernel` remain separate systems.
- `Kernel` is the Codex-orchestrated multi-agent fallback system used when Claude is rate-limited.
- Claude is not part of the Kernel implementation path.
- Shared model/provider secrets are resolved through stable canonical names rather than orchestrator-specific names.
- MBP and macmini can use the same shared-secret contract.
- GitHub Actions production workflows can run the watchdog, canary, mainframe, gate, and mobile progress paths on the merged main branch.

## Mainline Commits

- PR #702: `6213f7569c96e5d5f235649a95dab399ec4978f9`
  - MBP/macmini shared-secret continuity.
  - Repo-secret fallback contract.
  - Watchdog waiting-run detection.
  - Kernel launcher and prompt verification.
- PR #705: `a8a38988326ef3f90ffc78b322e6e71b8590189d`
  - Watchdog alert recovery-state persistence.
  - Empty watchdog state payload guard.
  - Static workflow checks for the recovery-state path.

## Production Evidence

Latest verified main head:

- `a8a38988326ef3f90ffc78b322e6e71b8590189d`

Verified successful production runs:

- `actionlint`: run `24537832007`, success
- `Detect Secrets`: run `24537832021`, success
- `fugue-orchestration-gate`: run `24537832030`, success
- `fugue-orchestrator-canary`: run `24537887562`, success
- `Fugue Mainframe`: runs `24537893846` and `24537895172`, success
- `fugue-watchdog`: run `24537844091`, success
- `kernel-mobile-progress`: run `24537858650`, success

The latest waiting-run query returned an empty list.

## Critical Issue Found and Fixed

### Problem

`FUGUE_WATCHDOG_ALERT_STATE` could retain stale active buckets after the system recovered.

The alert policy already knew how to prune inactive reasons, but the workflow only persisted state when an alert was emitted and delivery was confirmed. When `should_alert=false` and `state_update_required=true`, the computed recovery state was discarded.

Observed stale state before the fix:

```json
{"reason_buckets":{"mainframe-stale":"active"}}
```

### Fix

`.github/workflows/fugue-watchdog.yml` now has two persistence paths:

- alert path: persist only after confirmed Discord delivery
- recovery path: persist when no alert is due but state cleanup is required

Both paths refuse to overwrite `FUGUE_WATCHDOG_ALERT_STATE` when the next-state payload is empty.

### Result

After the merged fix, the production watchdog run executed the recovery-state persistence step successfully.

Current state:

```json
{"reason_buckets":{}}
```

## MBP Verification

Local MBP verification passed:

- `kernel launcher: ok`
- `k4 launcher: ok`
- `kernel-root helper: ok`
- `codex kernel guard: present`
- `zshrc snippet: ok`
- `codex prompts: ok`
- `secrets/fugue-secrets.enc`: mode `600`

Local tests passed:

- `bash tests/test-mbp-macmini-shared-secrets.sh`
- `bash tests/test-load-shared-secrets.sh`
- `bash tests/test-sync-gh-secrets-from-env.sh`
- `bash tests/test-install-kernel-launchers.sh`
- `bash tests/test-vote-launchers.sh`
- `bash scripts/check-codex-kernel-prompt.sh`
- `bash scripts/check-codex-vote-prompt.sh`
- `bash tests/test-watchdog-waiting-run-workflow.sh`
- `bash tests/test-watchdog-alert-policy.sh`
- `actionlint .github/workflows/fugue-watchdog.yml`

## macmini Verification

Primary macmini repository:

- `/Users/masayuki_otawara/fugue-orchestrator`
- HEAD: `a8a389883`
- branch: `main`

Runtime state:

- `com.cursorvers.fugue-primary-heartbeat`: loaded and running
- `com.cursorvers.fugue-selfheal`: loaded
- `com.cursorvers.fugue-primary-heartbeat-bootstrap`: loaded
- `secrets/fugue-secrets.enc`: mode `600`

macmini tests passed:

- `bash tests/test-watchdog-waiting-run-workflow.sh`
- `bash tests/test-watchdog-alert-policy.sh`

The macmini working tree contains runtime state under `.fugue` and local encrypted secret material. Those are operational state, not code drift for this version-up.

## Multi-Agent Review Notes

Critical review lanes converged on the same result:

- Codex: implemented and verified the watchdog recovery-state fix.
- GLM: approved the recovery-state design and requested an empty-payload guard, which was implemented.
- Cursor / Copilot: no confirmed blocking issue after review. One Copilot concern about an alert persistence gap was a false positive because the existing alert path still persists when `should_alert=true`.
- Subagent review: confirmed target completion required MBP, macmini, and production evidence, all of which were collected.

## Decisions Recorded

- `Kernel` remains a separate system from `FUGUE`.
- `Kernel` remains the Codex-orchestrated fallback path for Claude rate-limit conditions.
- Claude is used only in the FUGUE orchestrator context, not inside Kernel implementation.
- Repo secrets are acceptable as the fallback when org-secret management is blocked by permissions, provided canonical secret names remain stable and secret values are never printed.
- Watchdog recovery state must be persisted even when no alert is sent, because recovery cleanup is state mutation, not notification delivery.

## Remaining Non-Blocking Hardening

These items were outside the original completion gate. Follow-up hardening now has implementation support:

- `scripts/local/install-github-actions-tools.sh` checks/installs local `actionlint`
- `scripts/audit-org-secrets.sh --cleanup-shadows` plans safe repo-shadow cleanup
- failure-smoke drills cover locked Keychain, missing SOPS, and missing `gh` auth
- waiting-run drill is documented in `docs/runbook/fugue-watchdog-waiting-run-drill.md`
- canary and Manus diagnosis emit SLO-compatible metrics

The only remaining external gate is org-level permission for applying org-secret
cleanup. Without that permission, repo-secret fallback remains the designed safe
mode.

## Final Status

Development for the current FUGUE / Kernel version-up is complete.

The system is production-green on GitHub Actions, synchronized on MBP and macmini, and the discovered watchdog recovery-state bug has been fixed and verified in production.
