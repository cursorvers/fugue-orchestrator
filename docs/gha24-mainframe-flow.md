# GHA24 Mainframe Flow

## Purpose
Capture how a GHA24 request gets into the existing FUGUE mainframe path (tutti vote → optional Codex implementation) so readers can quickly understand the automation, guardrails, and monitoring around that "mainframe" stage of the pipeline.

## High-level flow
1. **Enter the mainframe path (two options).**
   - **CLI (two-step):** `scripts/gha24` creates the `fugue-task` issue with a minimal spec skeleton, then immediately edits the same issue to add the `tutti` label. Optional `--orchestrator codex|claude` (`GHA24_ORCHESTRATOR_PROVIDER`) and `--assist-orchestrator claude|codex|none` (`GHA24_ASSIST_ORCHESTRATOR_PROVIDER`) add per-issue routing metadata. CLI default mode remains implement unless review-only intent is explicit (or `--review` is passed). Implement mode adds implementation intent only; `--confirm-implement` is reserved for explicit critical/high-risk confirmation.
   - **Mobile / natural language:** Create a plain issue (optionally with `fugue-task`). Issue creation itself is now intake-only. The mainframe starts only when a trusted user posts `/vote` on the issue, or when an automation path explicitly adds `tutti` / dispatches the caller. This removes `opened` vs `issue_comment` races and makes the start signal auditable. Natural-language default mode remains review-first; implement requires explicit intent.
2. **Tutti consensus.** Once the caller/router resolves a trusted start signal, it dispatches `.github/workflows/fugue-tutti-caller.yml` explicitly. The `tutti` label is retained as an audit/control label, but the heavy mainframe workflow itself is now dispatch-only. `fugue-tutti-caller.yml` resolves main/assist orchestrators with this precedence: issue labels → body hints → natural-language hints → repo defaults (`FUGUE_MAIN_ORCHESTRATOR_PROVIDER`, `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER`, legacy fallback `FUGUE_ORCHESTRATOR_PROVIDER`). By default, `FUGUE_CLAUDE_ROLE_POLICY=flex` allows codex/claude main switching; setting `sub-only` demotes main `claude` to `codex` unless forced. Assist defaults to `claude` (co-orchestrator on by default). For assist `claude`, `FUGUE_CLAUDE_RATE_LIMIT_STATE=degraded` applies `FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY` (default `claude`), and `exhausted` falls back to `none` unless forced. Additionally, when `main=claude` and `assist=claude`, pressure guard applies (`FUGUE_CLAUDE_MAIN_ASSIST_POLICY=codex|none`, default `codex`) unless forced. In modified FUGUE normal operation, `main=claude` is finalized with `assist=codex` as the co-orchestrator lane to reduce Claude pressure while keeping multi-agent consensus. Then `.github/workflows/fugue-tutti-router.yml` runs a baseline vote, adds one **main-provider signal lane** (`codex-main-orchestrator` or `claude-main-orchestrator`), and adds optional specialist lanes as needed. Lane execution first resolves an execution profile: `subscription-strict` (self-hosted online), `subscription-paused` (self-hosted offline + `FUGUE_SUBSCRIPTION_OFFLINE_POLICY=hold`), `record-only` (primary executor authoritative, GitHub audit/handoff only), or `api-continuity` (explicit continuity policy/emergency mode). Continuity mode relaxes strict guards by default and can demote assist lanes via `FUGUE_EMERGENCY_ASSIST_POLICY` to keep votes moving. Lane depth is controlled by `FUGUE_MULTI_AGENT_MODE` (`standard|enhanced|max`, default `enhanced`), while GLM subagent fan-out is controlled by `FUGUE_GLM_SUBAGENT_MODE` (`off|paired|symphony`, default `paired`) in non-subscription profiles. Execution approval is decided by **role-weighted 2/3 consensus + HIGH-risk veto**.
3. **Codex implementation (optional).** When the issue carries implementation intent (`implement`, plus compatibility labels when present), the passed vote hands off to `fugue-codex-implement`; `implement-confirmed` is required only for critical/high-risk execution. The implement workflow checks whether the target repo is the current repo or a cross-repo target before installing `@openai/codex`, running Codex CLI, and creating a PR. Implement mode is gated by refinement loops (Plan → Parallel Simulation → Critical Review → Problem Fix → Replan) repeated `FUGUE_IMPLEMENT_REFINEMENT_CYCLES` times (default 3), then role-dialogue implementation loops (`Implementer/ Critic/ Integrator`) with rounds controlled by `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS` (default 2) and `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE` (default 1 when main=claude). It also enforces shared playbook artifacts (`.fugue/pre-implement/issue-<N>-todo.md`, `.fugue/pre-implement/lessons.md`) before PR creation is accepted.

## Guardrails
- **Spec skeleton.** Every issue created via `scripts/gha24` follows the template under `## GHA24 Task` / `## Spec (minimal)`, so every request documents `Goal`, `Must not` constraints, concrete acceptance criteria, and rollback instructions. The structured checklist keeps machine readers and judges consistent inputs across requests.
- **Single start signal.** Plain issue creation is intake-only; execution starts only from `/vote`, explicit `tutti` labeling, or direct `workflow_dispatch`. This removes the previous `opened` vs `/vote` race at the source.
- **Unattended runtime boundary.** Any future unattended runtime substrate may poll only already-authorized or already-claimed work. It must not treat raw issue creation as an execution start signal.
- **Router skip.** `fugue-task-router` short-circuits whenever an issue already carries `tutti` or `processing`, unless the current trigger is the explicit `tutti` label start itself. It also skips issues using the `## GHA24 Task` header (those are expected to be driven by `scripts/gha24`). This keeps the "plain fugue-task router" lane and the "GHA24 mainframe" lane from competing while still allowing `tutti` to be used as a deliberate manual start signal. `fugue-tutti-router` also skips reprocessing while `processing` is attached, except when `FUGUE_EMERGENCY_CONTINUITY_MODE=true` (inflight-only continuation).
- **PAT guard.** If a Codex implementation needs to target a repo other than the orchestrator, `fugue-codex-implement` refuses to run unless the optional `TARGET_REPO_PAT` secret is provided. Missing PATs result in a comment, a `needs-human` label, and no further automation, ensuring we never push cross-repo changes without explicit secrets consent.
- **Review-only guard.** If an issue requests review-only (`## Mode` = `review` or natural-language review-only intent), stale implementation labels are cleared or ignored before the mainframe handoff, so Codex implementation will not run accidentally.
- **Implement confirmation guard.** Non-critical implementation proceeds after passed consensus; critical/high-risk implementation is blocked until `implement-confirmed` exists. This prevents accidental autonomous changes at real approval boundaries without adding routine confirmation churn.
- **Refinement guard.** Implement workflow validates a preflight report with the 5-step loop for each configured cycle; missing sections fail the run before PR creation.
- **Implementation collaboration guard.** Implement workflow validates an implementation dialogue report (`Implementer Proposal`, `Critic Challenge`, `Integrator Decision`, `Applied Change`, `Verification`) for each configured round; missing sections fail the run before PR creation.
- **Task/Lessons guard.** Implement workflow validates `.fugue/pre-implement/issue-<N>-todo.md` (Plan/Checklist/Progress/Review + checkbox items) and requires `.fugue/pre-implement/lessons.md` to exist as the shared self-improvement ledger.
- **Risk-tier guard.** Implement workflow resolves `risk-tier (low|medium|high)` from issue text/labels to keep low-risk tasks lightweight while forcing deeper loops and review fan-out for high-risk tasks.
- **Conditional lessons guard.** Lessons updates become strict when correction/postmortem signals are present (`user-corrected`, `postmortem`, `regression`, `incident` or equivalent text cues).
- **Large-refactor guard.** `scripts/gha24` auto-adds `large-refactor` when task text indicates refactor/rewrite/migration, and implement workflow enforces `Candidate A/B + Failure Modes + Rollback Check` on every cycle.
- **Watchdog.** `.github/workflows/fugue-watchdog.yml` runs hourly to keep the mainframe healthy: it checks OpenAI/Z.ai connectivity, verifies that both `fugue-task-router` and `fugue-tutti-caller` have had a successful run in the last 3 hours, posts Discord/LINE alerts (when configured) if anything is stale, and works through open `fugue-task` issues that lack `processing`/`completed` labels by retriggering the router.
- **Claude state auto-recovery.** `fugue-watchdog` now auto-restores `FUGUE_CLAUDE_RATE_LIMIT_STATE` to `ok` only after cooldown and stability checks (no pending work, no recent fallback signals, connectivity healthy).
- **Switch canary.** `.github/workflows/fugue-orchestrator-canary.yml` runs daily and verifies two real-issue paths: regular `orchestrator:claude` request and forced `orchestrator-force:claude`.
- **Weekly review.** `.github/workflows/fugue-orchestration-weekly-review.yml` posts 7-day metrics (assist none/claude mix, high-risk escalation coverage, canary latest result) into the `fugue-status` thread.
- **Fast profile switch.** Switching `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` / `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER` immediately changes routing without code rollback.
- **Claude throttle guard.** `FUGUE_CLAUDE_RATE_LIMIT_STATE={ok|degraded|exhausted}` provides an operations kill-switch. With `FUGUE_CLAUDE_ROLE_POLICY=flex` (default), codex/claude main switching is allowed; use `sub-only` to enforce `main claude -> codex` unless forced. Assist `claude` degrades via `FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY={none|codex|claude}` on `degraded` (default `claude`) and is forced to `none` on `exhausted` unless per-issue forced.
- **Claude pressure guard.** `FUGUE_CLAUDE_MAIN_ASSIST_POLICY={codex|none}` avoids `main=claude` + `assist=claude` duplication by auto-adjusting assist unless forced, reducing fast rate-limit exhaustion.
- **Main-claude co-orchestrator invariant.** In modified FUGUE, `main=claude` is finalized with `assist=codex` by default (unless explicit force override), preserving dual-lane governance without doubling Claude pressure.
- **Capability-aware continuity guard.** In `api-continuity` / `api-standard`, when Claude direct credential is unavailable (or Claude is rate-limited), assist `claude` is auto-demoted to executable fallback (`codex` or `none`) unless forced, so resolved assist and runnable lanes stay consistent.
- **Claude assist mandatory gate.** When `FUGUE_CLAUDE_RATE_LIMIT_STATE=ok` and assist resolves to `claude`, `claude-opus-assist` direct success is required for auto-execution; missing direct success is treated as a veto signal.

## Mobile quick start
- Create a GitHub Issue using the template **FUGUE Task (Mobile / Natural Language)** (auto-adds label `fugue-task`), or manually add label `fugue-task`.
- To start the mainframe from a plain issue, post `/vote` as a trusted collaborator. Issue creation alone does not execute the mainframe anymore.
- Use structured fields when possible:
  - `Mainframe handoff`: `auto` or `manual`
  - `Execution mode`: `review` (default) or `implement`
  - `Implementation confirmation`: `pending` or `confirmed` (`confirmed` is required only for critical/high-risk implementation execution)
  - Optional provider/mode fields (`Main orchestrator provider`, `Assist orchestrator provider`, `Multi-agent mode`)
- Natural-language fallback markers are still supported:
  - `レビューのみ` (review-only)
  - `#manual` / `#no-gha24` / `manual only` (skip auto-mainframe handoff)
  - target repo in backticks, e.g. `cursorvers/cloudflare-workers-hub` (FUGUE adds `proj:<repo>` label + title prefix)

## Observability
- Tutti summaries, vote tallies, and Codex CLI output live directly on the originating GitHub issue so reviewers can trace decisions.
- `fugue-watchdog` issues Discord/LINE alerts with the last-success timestamps and hours-since metrics whenever the router/mainframe runners stall, which keeps the codex team aware of automation outages.
- The `processing` label heartbeat and `needs-human` escalations form a feedback loop: humans can step in when trust, PATs, or agency votes raise concerns.

## Operations Record (2026-02-22)
- Goal: verify codex/claude main orchestrator switching works under Claude throttle states without breaking review/implement routing.
- Deployed code baseline: commit `2e85de3` (`CLAUDE_ROLE_POLICY` default moved to `flex`; robust main/assist fallback preserved).
- Validation summary:
  - `bash -n` for changed shell scripts: pass
  - workflow YAML parse: pass
  - `actionlint -shellcheck= -pyflakes=`: pass
  - local simulation (`scripts/sim-orchestrator-switch.sh`): pass
- Live checks:
  - issue `#132` (`orchestrator:claude`, no force) under `FUGUE_CLAUDE_RATE_LIMIT_STATE=degraded` resolved main to `codex` as expected.
  - issue `#133` (`orchestrator:claude` + force) resolved main to `claude` as expected.
  - workflow evidence: `https://github.com/cursorvers/fugue-orchestrator/actions/runs/22278213098`
- Current operational note:
  - `FUGUE_CLAUDE_RATE_LIMIT_STATE` remains `degraded`; claude should be treated as constrained capacity until it returns to `ok`.

## Operations Record (2026-04-19)
- Goal: prevent accidental Git operations from binding to parent state repositories at `/Users/masayuki_otawara` and `/Users/masayuki_otawara/Dev`.
- Risk addressed:
  - Running `git status`, `git add .`, or similar commands from non-repository work directories such as `~/.local/share/x-auto` or `~/Dev/tmp` could previously bind to the nearest parent repository and expose or stage unrelated home/workspace files.
  - The home repository tracks only a small local-state set, while `~/Dev` is itself a parent orchestration repository with many nested standalone repositories. Both needed broad-add protection.
- Implemented guards:
  - `GIT_CEILING_DIRECTORIES=$HOME:$HOME/Dev` is initialized idempotently for zsh, bash, and POSIX login shells.
  - The current user launchd environment was updated with the same ceiling for this login session.
  - Home and Dev parent repositories now use local `status.showUntrackedFiles=no` for normal status output.
  - Home and Dev parent repositories have local `.git/info/exclude` `/*` guards, so broad `git add .` does not stage untracked home files, generated workspaces, or nested project trees. New parent-repo files must be added deliberately with `git add -f <path>`.
  - Explicit operations remain available through `git -C "$HOME" ...`, `git -C "$HOME/Dev" ...`, or the shell helpers `home-state-git` and `dev-root-git`.
- Validation summary:
  - `zsh -lc` from `~/.local/share/x-auto`, `~/.codex/skills/x-auto`, and `~/Dev/tmp` returns `fatal: not a git repository`, proving parent repo discovery is blocked for routine shell work.
  - `zsh -lc` from `~/Dev/x-auto` and `~/fugue-orchestrator` resolves their real nested repositories normally.
  - `env -u GIT_CEILING_DIRECTORIES bash -lc` still receives the guard via bash startup files.
  - POSIX login `sh -l` receives the guard via `~/.profile`.
  - Pure non-login `sh` does not read shell startup files, but home/Dev `/*` excludes still block broad-add accidents.
  - `git -C "$HOME" add -n .` stages nothing.
  - `git -C "$HOME/Dev" add -n .` stages only existing tracked modifications, not untracked project trees.
- Current operational note:
  - Objective completion is approximately 98%. Remaining 2% is a separate structural migration: moving the home/Dev parent state repositories into dedicated state directories. That is intentionally not done here because it changes repository identity and would require a separate rollback plan.
  - `~/Dev` still has pre-existing tracked modifications unrelated to this guard. They are not untracked-noise risk, but they should be handled in a separate cleanup slice.
