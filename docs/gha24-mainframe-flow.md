# GHA24 Mainframe Flow

## Purpose
Capture how a GHA24 request gets into the existing FUGUE mainframe path (tutti vote → optional Codex implementation) so readers can quickly understand the automation, guardrails, and monitoring around that "mainframe" stage of the pipeline.

## High-level flow
1. **Enter the mainframe path (two options).**
   - **CLI (two-step):** `scripts/gha24` creates the `fugue-task` issue with a minimal spec skeleton, then immediately edits the same issue to add the `tutti` label. Separating creation from the `tutti` label keeps the mainframe path anchored to a single explicit consent action (label `tutti`), and prevents accidental multi-triggering when other labels are present.
   - **Mobile / natural language:** Create a plain `fugue-task` issue (no `## GHA24 Task` header) and include an explicit "complete it" phrase like `完遂` / `自走` / `最後まで`. `fugue-task-router` will add `tutti` (and by default also `codex-implement`) and leave an audit comment that it handed off to GHA24.
2. **Tutti consensus.** Adding label `tutti` fires `.github/workflows/fugue-tutti-caller.yml`, which downloads the issue text, runs the `fugue-tutti-router` agent vote, and only triggers `fugue-codex-implement` once the vote passes with no HIGH-risk findings. The router runs three parallel agents, integrates their JSON results, and posts a summary comment to the originating issue (the comment is the audit log).
3. **Codex implementation (optional).** When the issue carries `codex-implement`, the passed vote hands off to `fugue-codex-implement`, which checks whether the target repo is the current repo or a cross-repo target before installing `@openai/codex`, running Codex CLI, and creating a PR.

## Guardrails
- **Spec skeleton.** Every issue created via `scripts/gha24` follows the template under `## GHA24 Task` / `## Spec (minimal)`, so every request documents `Goal`, `Must not` constraints, concrete acceptance criteria, and rollback instructions. The structured checklist keeps machine readers and judges consistent inputs across requests.
- **Router skip.** `fugue-task-router` short-circuits whenever an issue already carries `tutti` or `processing`, and it also skips issues using the `## GHA24 Task` header (those are expected to be driven by `scripts/gha24`). This keeps the "plain fugue-task router" lane and the "GHA24 mainframe" lane from competing. A similar guard prevents `fugue-tutti-router` from reprocessing the same issue while `processing` is attached.
- **PAT guard.** If a Codex implementation needs to target a repo other than the orchestrator, `fugue-codex-implement` refuses to run unless the optional `TARGET_REPO_PAT` secret is provided. Missing PATs result in a comment, a `needs-human` label, and no further automation, ensuring we never push cross-repo changes without explicit secrets consent.
- **Watchdog.** `.github/workflows/fugue-watchdog.yml` runs hourly to keep the mainframe healthy: it checks OpenAI/Z.ai connectivity, verifies that both `fugue-task-router` and `fugue-tutti-caller` have had a successful run in the last 3 hours, posts a Discord alert if anything is stale, and works through open `fugue-task` issues that lack `processing`/`completed` labels by retriggering the router.

## Mobile quick start
- Create a GitHub Issue and add label `fugue-task`.
- In the body, include:
  - `完遂` (hands off to GHA24 mainframe)
  - Optional: `レビューのみ` (do not add `codex-implement`)

## Observability
- Tutti summaries, vote tallies, and Codex CLI output live directly on the originating GitHub issue so reviewers can trace decisions.
- `fugue-watchdog` issues Discord alerts with the last-success timestamps and hours-since metrics whenever the router/mainframe runners stall, which keeps the codex team aware of automation outages.
- The `processing` label heartbeat and `needs-human` escalations form a feedback loop: humans can step in when trust, PATs, or agency votes raise concerns.
