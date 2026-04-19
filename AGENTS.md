# AGENTS.md - FUGUE Orchestration SSOT

This file is the single source of truth for the active FUGUE and GitHub workflow orchestration
behavior in this repository.
Adapter files such as `CLAUDE.md` must stay thin and reference this file.

Important scope boundary:

- `AGENTS.md` governs the currently active FUGUE runtime, GitHub workflows, and hybrid conductor
  behavior.
- `docs/requirements-gpt54-codex-kernel.md` and related `docs/kernel-*` files govern the future
  Kernel sovereign path and `/kernel` design work.
- If the task is about the current production GitHub workflow path, `AGENTS.md` is authoritative.
- If the task is explicitly about `Kernel` design or implementation, Kernel docs define the target
  state and may intentionally differ from active FUGUE defaults.

## 1. Context Loading Policy

- Default load: this file only.
- Load additional docs on demand only when blocked.
- Avoid loading long historical rationale unless needed for a decision.
- Keep adapter files short to reduce repeated context overhead.
- Sections 4-11 details are split into `docs/agents/` for on-demand loading. See §4 Reference Index below.

## 2. Control Plane Contract

- Main orchestrator is provider-agnostic by design.
- Active FUGUE runtime default is `claude` main with `codex` execution provider.
- Future `Kernel` runtime target remains `codex`-first single-sovereign; do not treat the active
  FUGUE default as a Kernel doctrine.
- Operational default is `claude` (main conductor), with `codex` as execution provider.
- **Hybrid Conductor Mode**: When `FUGUE_EXECUTION_PROVIDER` differs from main orchestrator:
  - Main orchestrator (Claude) handles routing, MCP operations, and Tutti signal.
  - Execution provider (Codex) handles all code implementation.
  - Implementation profile follows `execution_provider` (codex-full), not main (claude-light).
  - Multi-agent mode is NOT locked to `standard` in Hybrid — full lane depth applies.
- **Hybrid Handoff Contract** (applies when Hybrid Conductor Mode is active):
  - Claude resolves routing, MCP artifacts, and Tutti voting topology.
  - Codex receives implementation dispatch via `fugue-codex-implement.yml` with `execution_profile=codex-full`.
  - MCP operations (Pencil, Stripe, Supabase, etc.) are Claude-exclusive; never bridged through Codex.
  - Implementation parameters (`preflight_cycles`, `dialogue_rounds`, `multi_agent_mode`) follow `execution_profile`, not `orchestration_profile`.
- **MCP REST Bridge** (v8.6): CI can directly access Supabase and Stripe via REST API, bypassing MCP protocol.
  - Bridge script: `scripts/lib/mcp-rest-bridge.sh`
  - Supabase: PostgREST API with `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`
  - Stripe: REST API with existing `STRIPE_API_KEY`
  - CI-inaccessible MCP (Claude-session-only): Pencil, Excalidraw, Slack, Vercel
  - Scorecard `mcp_calls` counter now reflects actual bridge calls instead of hardcoded `0`.
- **Hybrid Failover** (when `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted` during Hybrid):
  - Throttle guard demotes main to `codex`, deactivating Hybrid Conductor Mode.
  - All tasks run through codex-only (no MCP access). MCP-dependent tasks will fail and require manual retry after Claude recovery.
  - Partial failover (MCP task queuing) is reserved for future implementation.
- Operational default is `codex` (both main and execution) when `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted`.
- `codex` serves as assist sidecar when Claude is main (architectural invariant).
- Claude subscription assumption is `FUGUE_CLAUDE_PLAN_TIER=max20` with `FUGUE_CLAUDE_MAX_PLAN=true`.
- State transitions and PR actions are owned by control plane workflows, not by sidecar advice.
- **v8.5 Tuning** (Claude consumption optimization):
  - `FUGUE_CLAUDE_TRANSLATOR_THRESHOLD` raised to `90` (from `75`) to reduce translation gateway triggers.
  - Claude assist lanes reduced to 1 in subscription mode (Opus only).
  - Target: Claude weekly consumption ≤ 30-40% of MAX20 allocation.

## 3. Provider Resolution Contract

Main resolution order:
1. Issue label (`orchestrator:claude` or `orchestrator:codex`)
2. Issue body hint (`## Orchestrator provider` or `orchestrator provider: ...`)
3. Repository variable `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` (legacy fallback `FUGUE_ORCHESTRATOR_PROVIDER`)
4. Fallback default `claude`

Execution provider resolution:
1. Repository variable `FUGUE_EXECUTION_PROVIDER`
2. Fallback: same as resolved main provider
- When `FUGUE_EXECUTION_PROVIDER` differs from resolved main, Hybrid Conductor Mode activates.

Assist resolution order:
1. Issue label (`orchestrator-assist:claude|codex|none`)
2. Issue body hint (`## Assist orchestrator provider` or inline hint)
3. Repository variable `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER`
4. Fallback default `claude`

Throttle guard:
- If resolved **main** provider is `claude` and state is `degraded` or `exhausted`, auto-fallback to `codex`.
- If resolved **assist** provider is `claude` and state is `exhausted`, auto-fallback to `none`.
- If resolved **main** is `claude` and resolved **assist** is also `claude`, apply pressure guard (`FUGUE_CLAUDE_MAIN_ASSIST_POLICY=codex|none`, default `codex`) unless forced.
- Per-issue override: label `orchestrator-force:claude` or CLI `--force-claude`.

Auditability:
- Fallback decisions must be commented on the issue.
- CLI pre-fallback must leave an explicit audit comment.

User-approval friction rule:
- For both `claude` main orchestrator and `codex` main orchestrator paths, non-critical execution
  must use Tutti / Kernel council approval as the authorization path after `ok_to_execute=true`.
- Do not ask the user for an additional routine approval when weighted `2/3` consensus passes,
  no HIGH-risk veto exists, and the current run has consensus evidence.
- Human approval remains mandatory only for critical, destructive, irreversible,
  secrets/auth/billing/trust-boundary, materially ambiguous, or high-impact external side-effect
  actions without rollback.
- Any adapter that still requires approval must record why the action is critical or why local
  evidence/consensus could not satisfy the gate.

Completion reporting:
- When development work is completed, the active agent must always display a completion report to
  the user before ending the turn or workflow.
- The completion report must state what changed, where it was changed, what verification was run,
  and whether any residual risks, skipped checks, dirty worktree entries, or follow-up tasks remain.
- Do not treat background automation, PR creation, merge completion, or issue label changes as a
  substitute for this user-visible report.
- If the work cannot be completed, report the blocker and the exact remaining task instead of
  emitting a completion-style summary.

## 4. Reference Index

Sections 4-11 are split into separate files for on-demand loading.
Load only the section relevant to your current task.

| Original § | Topic | File |
|------------|-------|------|
| §4 | Execution/Evaluation Lanes | `docs/agents/execution-lanes.md` |
| §5 | Safety and Governance | `docs/agents/safety-governance.md` |
| §6 | Workflow Ownership | `docs/agents/workflow-ownership.md` |
| §7 | Adapter Contract | `docs/agents/adapter-contract.md` |
| §8 | Simulation Runbook | `docs/agents/simulation-runbook.md` |
| §9 | Shared Skills Baseline | `docs/agents/shared-skills.md` |
| §10 | Shared Workflow Playbook | `docs/agents/shared-playbook.md` |
| §11 | Local Linked Systems | `docs/agents/linked-systems.md` |
