# Source: AGENTS.md §6 — Workflow Ownership
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 6. Workflow Ownership

- Issue intake and natural-language handoff:
  - `.github/workflows/fugue-task-router.yml`
  - Default behavior: `fugue-task` issues auto-handoff into the intake/mainframe review path unless
    manual opt-out markers are present.
  - Natural-language default mode is review-first; implement must be explicit and confirmed.
- Start-signal arbitration:
  - plain GitHub issue creation is intake, not execution authority
  - trusted execution start signals are `/vote`, explicit `tutti`, or `workflow_dispatch`
  - intake/mainframe review routing must not be interpreted as implicit approval to execute
  - future unattended runtime work must poll only already-authorized / already-claimed work, not
    bypass this start-signal contract
- Mainframe orchestration gate:
  - `.github/workflows/fugue-tutti-caller.yml`
- Tutti quorum integration:
  - `.github/workflows/fugue-tutti-router.yml`
- Implementation engine:
  - `.github/workflows/fugue-codex-implement.yml`
- Operational health:
  - `.github/workflows/fugue-watchdog.yml`
  - `.github/workflows/fugue-status.yml`
- Cross-repo dispatch-back (v8.6):
  - Consumer repos receive FUGUE results via `repository_dispatch` event type `fugue-linked-result`.
  - Triggered from `run-linked-systems.sh` when `CONSUMER_REPO` and `TARGET_REPO_PAT` are set.
  - Consumer repos install `.github/workflows/templates/fugue-result-receiver.yml` to post results to issues.
  - Payload: `{issue, status, success_count, error_count, mode, source_issue}`.
- Submodule auto-sync (v8.6):
  - `.github/workflows/fugue-submodule-sync.yml` auto-updates `.claude` submodule on `claude-config` push.
  - Creates auto-merge PR on ref change; requires `TARGET_REPO_PAT` for cross-repo checkout.
