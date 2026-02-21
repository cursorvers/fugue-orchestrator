# GHA24 Mainframe Flow

## Purpose
Capture how a GHA24 request gets into the existing FUGUE mainframe path (tutti vote → optional Codex implementation) so readers can quickly understand the automation, guardrails, and monitoring around that "mainframe" stage of the pipeline.

## High-level flow
1. **Enter the mainframe path (two options).**
   - **CLI (two-step):** `scripts/gha24` creates the `fugue-task` issue with a minimal spec skeleton, then immediately edits the same issue to add the `tutti` label. Separating creation from the `tutti` label keeps the mainframe path anchored to a single explicit consent action (label `tutti`), and prevents accidental multi-triggering when other labels are present. Optional `--orchestrator codex|claude` (or `GHA24_ORCHESTRATOR_PROVIDER`) adds explicit provider metadata for this issue only. If `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded`/`exhausted`, `--orchestrator claude` is auto-fallbacked to `codex` unless `--force-claude` is set.
   - **Mobile / natural language:** Create a plain `fugue-task` issue (no `## GHA24 Task` header) and include an explicit "complete it" phrase like `完遂` / `自走` / `最後まで`. `fugue-task-router` will add `tutti` (and by default also `implement` + provider compatibility label: `codex-implement` or `claude-implement`) and leave an audit comment that it handed off to GHA24. Provider resolution is `orchestrator:*` label → body hint (`## Orchestrator provider` or `orchestrator provider: ...`) → repo default, with auto-fallback to `codex` if Claude is marked degraded/exhausted (override label: `orchestrator-force:claude`). Because label edits made by `GITHUB_TOKEN` do not trigger other workflows, the router also dispatches the mainframe workflow directly.
2. **Tutti consensus.** Adding label `tutti` fires `.github/workflows/fugue-tutti-caller.yml`, which downloads the issue text and resolves orchestrator profile in this order: `orchestrator:*` issue label → `## Orchestrator provider` / inline provider hint in body → repo variable `FUGUE_ORCHESTRATOR_PROVIDER` (fallback `codex`). If the resolved provider is `claude` and `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted`, FUGUE auto-switches to `codex` (unless forced) and logs the reason on the issue. Then it runs the `fugue-tutti-router` vote, and only triggers `fugue-codex-implement` once the vote passes with no HIGH-risk findings and an implementation intent label (`implement` / `codex-implement` / `claude-implement`) exists. The router dynamically adds specialist lanes (Gemini for visual/UI intent, xAI for X/Twitter/realtime intent), and all core review lanes include GLM (`glm-5.0`) by default.
3. **Codex implementation (optional).** When the issue carries an implementation intent label (`implement` / `codex-implement` / `claude-implement`), the passed vote hands off to `fugue-codex-implement`, which checks whether the target repo is the current repo or a cross-repo target before installing `@openai/codex`, running Codex CLI, and creating a PR.

## Guardrails
- **Spec skeleton.** Every issue created via `scripts/gha24` follows the template under `## GHA24 Task` / `## Spec (minimal)`, so every request documents `Goal`, `Must not` constraints, concrete acceptance criteria, and rollback instructions. The structured checklist keeps machine readers and judges consistent inputs across requests.
- **Router skip.** `fugue-task-router` short-circuits whenever an issue already carries `tutti` or `processing`, and it also skips issues using the `## GHA24 Task` header (those are expected to be driven by `scripts/gha24`). This keeps the "plain fugue-task router" lane and the "GHA24 mainframe" lane from competing. A similar guard prevents `fugue-tutti-router` from reprocessing the same issue while `processing` is attached.
- **PAT guard.** If a Codex implementation needs to target a repo other than the orchestrator, `fugue-codex-implement` refuses to run unless the optional `TARGET_REPO_PAT` secret is provided. Missing PATs result in a comment, a `needs-human` label, and no further automation, ensuring we never push cross-repo changes without explicit secrets consent.
- **Review-only guard.** If an issue requests review-only (`## Mode` = `review` or natural-language review-only intent), stale implementation labels are cleared or ignored before the mainframe handoff, so Codex implementation will not run accidentally.
- **Watchdog.** `.github/workflows/fugue-watchdog.yml` runs hourly to keep the mainframe healthy: it checks OpenAI/Z.ai connectivity, verifies that both `fugue-task-router` and `fugue-tutti-caller` have had a successful run in the last 3 hours, posts a Discord alert if anything is stale, and works through open `fugue-task` issues that lack `processing`/`completed` labels by retriggering the router.
- **Fast profile switch.** Switching `FUGUE_ORCHESTRATOR_PROVIDER` between `codex` and `claude` immediately changes lane-profile resolution without code rollback.
- **Claude throttle guard.** `FUGUE_CLAUDE_RATE_LIMIT_STATE={ok|degraded|exhausted}` provides an operations kill-switch; degraded/exhausted automatically routes new work to `codex` while preserving a per-issue force override.

## Mobile quick start
- Create a GitHub Issue using the template **FUGUE Task (Mobile / Natural Language)** (auto-adds label `fugue-task`), or manually add label `fugue-task`.
- In the body, include:
  - `完遂` (hands off to GHA24 mainframe)
  - Optional: `レビューのみ` (do not add implementation intent labels)
  - Optional: a target repo in backticks, e.g. `cursorvers/cloudflare-workers-hub` (FUGUE will add a `proj:<repo>` label and prefix the issue title for easy scanning)

## Observability
- Tutti summaries, vote tallies, and Codex CLI output live directly on the originating GitHub issue so reviewers can trace decisions.
- `fugue-watchdog` issues Discord alerts with the last-success timestamps and hours-since metrics whenever the router/mainframe runners stall, which keeps the codex team aware of automation outages.
- The `processing` label heartbeat and `needs-human` escalations form a feedback loop: humans can step in when trust, PATs, or agency votes raise concerns.
