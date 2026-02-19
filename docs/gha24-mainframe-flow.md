# GHA24 Mainframe Flow

## Purpose
Capture how a GHA24 request gets into the existing FUGUE mainframe path (tutti vote → optional Codex implementation) so readers can quickly understand the automation, guardrails, and monitoring around that "mainframe" stage of the pipeline.

## High-level flow
1. **Two-step Tutti trigger.** The `scripts/gha24` helper creates the `fugue-task` issue with a minimal spec skeleton, then immediately edits the same issue to add the `tutti` label. Separating creation from the `tutti` label keeps the mainframe path anchored to a single explicit consent action (label `tutti`), and prevents accidental multi-triggering when other labels are present.
2. **Tutti consensus.** Adding label `tutti` fires `.github/workflows/fugue-tutti-caller.yml`, which downloads the issue text, resolves orchestrator profile via repo variable `FUGUE_ORCHESTRATOR_PROVIDER` (`codex` default), runs the `fugue-tutti-router` vote, and only triggers `fugue-codex-implement` once the vote passes with no HIGH-risk findings. The router picks its parallel lane matrix by profile (`claude`: 4-lane, `codex`: 6-lane) and posts an integrated summary comment to the originating issue (audit log).
3. **Codex implementation (optional).** When the issue also carries `codex-implement`, the passed vote hands off to `fugue-codex-implement`, which checks whether the target repo is the current repo or a cross-repo target before installing `@openai/codex`, running Codex CLI, and creating a PR.

## Guardrails
- **Spec skeleton.** Every issue created via `scripts/gha24` follows the template under `## GHA24 Task` / `## Spec (minimal)`, so every request documents `Goal`, `Must not` constraints, concrete acceptance criteria, and rollback instructions. The structured checklist keeps machine readers and judges consistent inputs across requests.
- **Router skip.** `fugue-task-router` short-circuits whenever an issue already carries `tutti`, `processing`, or the `GHA24 Task` header: it only services plain `fugue-task` issues. A similar guard prevents `fugue-tutti-router` from reprocessing the same issue while `processing` is attached, so GHA24 requests stay in their dedicated lane rather than competing with manual Claude-triggered issues.
- **PAT guard.** If a Codex implementation needs to target a repo other than the orchestrator, `fugue-codex-implement` refuses to run unless the optional `TARGET_REPO_PAT` secret is provided. Missing PATs result in a comment, a `needs-human` label, and no further automation, ensuring we never push cross-repo changes without explicit secrets consent.
- **Watchdog.** `.github/workflows/fugue-watchdog.yml` runs hourly to keep the mainframe healthy: it checks OpenAI/Z.ai connectivity, verifies that both `fugue-task-router` and `fugue-tutti-caller` have had a successful run in the last 3 hours, posts a Discord alert if anything is stale, and works through open `fugue-task` issues that lack `processing`/`completed` labels by retriggering the router.
- **Fast rollback.** Switching `FUGUE_ORCHESTRATOR_PROVIDER` from `codex` back to `claude` immediately restores the prior lane profile without code rollback.

## Observability
- Tutti summaries, vote tallies, and Codex CLI output live directly on the originating GitHub issue so reviewers can trace decisions.
- `fugue-watchdog` issues Discord alerts with the last-success timestamps and hours-since metrics whenever the router/mainframe runners stall, which keeps the codex team aware of automation outages.
- The `processing` label heartbeat and `needs-human` escalations form a feedback loop: humans can step in when trust, PATs, or agency votes raise concerns.
