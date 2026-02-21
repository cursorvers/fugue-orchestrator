# GHA24 Mainframe Flow

## Purpose
Capture how a GHA24 request gets into the existing FUGUE mainframe path (tutti vote → optional Codex implementation) so readers can quickly understand the automation, guardrails, and monitoring around that "mainframe" stage of the pipeline.

## High-level flow
1. **Enter the mainframe path (two options).**
   - **CLI (two-step):** `scripts/gha24` creates the `fugue-task` issue with a minimal spec skeleton, then immediately edits the same issue to add the `tutti` label. Optional `--orchestrator codex|claude` (`GHA24_ORCHESTRATOR_PROVIDER`) and `--assist-orchestrator claude|codex|none` (`GHA24_ASSIST_ORCHESTRATOR_PROVIDER`) add per-issue routing metadata.
   - **Mobile / natural language:** Create a plain `fugue-task` issue (no `## GHA24 Task` header) and include an explicit "complete it" phrase like `完遂` / `自走` / `最後まで`. `fugue-task-router` adds `tutti`, normalizes orchestrator labels (`orchestrator:*`, `orchestrator-assist:*`), and dispatches the mainframe workflow directly.
2. **Tutti consensus.** Adding label `tutti` fires `.github/workflows/fugue-tutti-caller.yml`, which resolves main/assist orchestrators with this precedence: issue labels → body hints → repo defaults (`FUGUE_MAIN_ORCHESTRATOR_PROVIDER`, `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER`, legacy fallback `FUGUE_ORCHESTRATOR_PROVIDER`). If `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded`/`exhausted` and not forced, main `claude` falls back to `codex`, assist `claude` falls back to `none`. Then `.github/workflows/fugue-tutti-router.yml` runs a **6-lane baseline vote** (Codex3 + GLM3) and adds optional specialist lanes (Claude assist, Gemini, xAI) as needed.
3. **Codex implementation (optional).** When the issue carries an implementation intent label (`implement` / `codex-implement` / `claude-implement`), the passed vote hands off to `fugue-codex-implement`, which checks whether the target repo is the current repo or a cross-repo target before installing `@openai/codex`, running Codex CLI, and creating a PR.

## Guardrails
- **Spec skeleton.** Every issue created via `scripts/gha24` follows the template under `## GHA24 Task` / `## Spec (minimal)`, so every request documents `Goal`, `Must not` constraints, concrete acceptance criteria, and rollback instructions. The structured checklist keeps machine readers and judges consistent inputs across requests.
- **Router skip.** `fugue-task-router` short-circuits whenever an issue already carries `tutti` or `processing`, and it also skips issues using the `## GHA24 Task` header (those are expected to be driven by `scripts/gha24`). This keeps the "plain fugue-task router" lane and the "GHA24 mainframe" lane from competing. A similar guard prevents `fugue-tutti-router` from reprocessing the same issue while `processing` is attached.
- **PAT guard.** If a Codex implementation needs to target a repo other than the orchestrator, `fugue-codex-implement` refuses to run unless the optional `TARGET_REPO_PAT` secret is provided. Missing PATs result in a comment, a `needs-human` label, and no further automation, ensuring we never push cross-repo changes without explicit secrets consent.
- **Review-only guard.** If an issue requests review-only (`## Mode` = `review` or natural-language review-only intent), stale implementation labels are cleared or ignored before the mainframe handoff, so Codex implementation will not run accidentally.
- **Watchdog.** `.github/workflows/fugue-watchdog.yml` runs hourly to keep the mainframe healthy: it checks OpenAI/Z.ai connectivity, verifies that both `fugue-task-router` and `fugue-tutti-caller` have had a successful run in the last 3 hours, posts a Discord alert if anything is stale, and works through open `fugue-task` issues that lack `processing`/`completed` labels by retriggering the router.
- **Fast profile switch.** Switching `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` / `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER` immediately changes routing without code rollback.
- **Claude throttle guard.** `FUGUE_CLAUDE_RATE_LIMIT_STATE={ok|degraded|exhausted}` provides an operations kill-switch; degraded/exhausted routes main `claude -> codex`, assist `claude -> none` unless per-issue forced.

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
