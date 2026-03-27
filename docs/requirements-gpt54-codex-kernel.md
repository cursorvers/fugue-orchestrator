# Requirements: GPT-5.4 Codex Kernel Orchestration

## Naming

The working and default name of this next-generation Codex-first orchestration system is:

- `Kernel`

Interpretation:

- `FUGUE` remains the parent design lineage and governance philosophy.
- `Kernel` refers to the new Codex-centered orchestration engine that inherits FUGUE doctrines while consolidating control-plane ownership into a single trusted core.

## 1. Goal

Build the next FUGUE lineage as a `gpt-5.4`-first orchestration system that preserves FUGUE's governance strengths without inheriting the old dual-orchestrator complexity.

The new system must:
- keep `gpt-5.4` as the default control-plane owner
- preserve multi-model council safety for autonomous progress
- retain Claude-powered peripheral execution where Claude-native workflows remain stronger
- maximize Codex multi-agent and `gpt-5.3-codex-spark` speed for day-to-day development
- keep the core protocol provider-neutral enough that a future `Claude main` mode can be restored via an explicit adapter rather than a forked architecture

## 2. Doctrines To Preserve From FUGUE

These principles are worth migrating as-is or with minimal translation:

1. `Governance-first`
   - Safety and execution approval live in the orchestration layer, not in ad hoc post-processing.

2. `Fixed-cost first, metered last`
   - Prefer subscription-backed models and CLI/free-tier tools before metered specialists.

3. `Multi-voice council`
   - Do not trust a single model for write/ship decisions when another strong fixed-cost reviewer is available.

4. `Risk-gated autonomy`
   - User approval is required only for destructive, irreversible, or trust-boundary-crossing actions.
   - Routine development should be able to proceed through council approval.

5. `Evidence before done`
   - Planning, verification, and concrete evidence are mandatory before completion.

6. `Specialist by capability`
   - Use the strongest provider for a capability, but keep state ownership centralized.

7. `PDCA-first before rollout`
   - Kernel must prefer repeated hypothesis-testing cycles before promoting a pattern into the default runtime.
   - Validation harnesses are part of the product, not disposable scaffolding.

8. `Quality x speed, not quality vs speed`
   - The system must optimize for high-confidence speed, not raw speed alone.
   - Fast paths must be paired with cheap verification and explicit promotion rules.

9. `Protected business interfaces`
   - Production systems tied to business operations must be treated as protected contracts.
   - Kernel should orchestrate around them before attempting structural consolidation.

## 3. Doctrines To Retire

These old assumptions must not constrain the new kernel:

1. `Main orchestrator never executes`
   - This was a Claude rate-limit optimization, not a timeless architectural law.
   - `gpt-5.4` may directly read, reason, tool-call, draft, patch, and integrate low-risk work.

2. `Dual main/assist orchestration as a default`
   - The new system has one active sovereign orchestrator per run.
   - Claude is not a co-owner of control-plane state by default.
   - If Claude is restored as main in the future, it must do so through the same Kernel adapter contract as Codex.

3. `Claude-light as a default execution ceiling`
   - Claude rate-limit protection should survive, but only inside Claude-specific lanes.
   - It must not throttle Codex multi-agent capacity.

## 4. System Roles

| Component | Role | Voting | Default Cost Policy |
|-----------|------|--------|---------------------|
| `gpt-5.4` | default orchestrator, planner, integrator, judge | yes | fixed-cost first |
| `gpt-5.3-codex-spark` | high-speed parallel workers | yes | fixed-cost first |
| `Claude Code / Claude executor` | adapter worker for Claude-native capabilities | yes, when participating in council | fixed-cost first |
| `GLM (Z.ai)` | baseline reviewer, critic, invariants, math | yes | fixed-cost first |
| `Manus` | artifact engine, wide research, browser-heavy execution | no by default | fixed-cost first |
| `Gemini` | UI/UX and visual review specialist | conditional yes | CLI/free-first, metered fallback |
| `xAI` | realtime / X search specialist | conditional yes | metered last |

### 4.0.1 Subscription / Cost Priority

When multiple providers can plausibly satisfy the same lane, Kernel should prefer them in this order:

1. `Codex CLI / ChatGPT Pro`
2. `Claude CLI / Max`
3. `GLM (Z.ai Pro)`
4. `Gemini CLI`
5. `Gemini API` fallback
6. `xAI API`
7. `Anthropic API`

Important distinction:

- `GLM` remains third in cost priority because it is part of the fixed-cost subscription stack for this workspace.
- The current execution path for `GLM` is still API-backed, but it should be treated as subscription-priority in lane selection and budget policy.
- `Claude` stays ahead of `GLM` only for local subscription execution; Claude rate-limit handling must remain bounded and must not dominate architecture.

## 4.1 Orchestrator Adapter Contract

Kernel should separate `control-plane protocol` from `provider implementation`.

Core rule:

- Kernel owns the orchestration protocol.
- A provider becomes `main orchestrator` only by satisfying that protocol through an adapter.

Required adapter outputs:

- intake normalization
- task classification payload
- lane topology selection request
- council vote envelope
- `ok_to_execute` decision payload
- run trace / artifact schema
- fallback reason reporting

Initial adapter set:

- `codex-sovereign` (default)
- `claude-executor` (non-sovereign)
- optional future `claude-sovereign-compat` adapter
- optional legacy `fugue-bridge` adapter for migration

Machine-readable sovereign adapter contract source:

- `config/orchestration/sovereign-adapters.json`

Important constraint:

- Future `Claude main` is allowed only as an adapter mode.
- Kernel core must never again depend structurally on Claude-specific limits or assumptions.

## 5. Kernel Responsibilities

`gpt-5.4` owns all default control-plane responsibilities:

- intake normalization
- task-shape classification
- lane topology selection
- proposal synthesis
- vote aggregation and conflict resolution
- `ok_to_execute` decision
- GitHub state transitions
- linked-system dispatch ordering
- final reporting

No non-Codex provider should own issue state, execution approval, or final merge judgment unless it is running through a first-class Kernel sovereign adapter.

## 5.1 Codex Harness Core

Kernel should implement the equivalent of the old `Claude harness`, but under Codex ownership.

`Codex Harness Core` is responsible for:

- execution engine resolution
- runner selection
- spark fan-out orchestration
- verification loop scheduling
- continuity fallback
- artifact normalization
- run trace and observability output

Claude remains outside this core as an executor adapter by default.

## 5.2 Unattended Runtime Substrate

Kernel should implement an unattended runtime substrate under Codex ownership.

This layer may absorb `Symphony`-like runtime primitives, but it must remain subordinate to the
Kernel sovereign core.

Required substrate responsibilities:

- daemonized intake / refresh loop
- issue or queue polling with bounded dispatch
- deterministic claim / idempotency guards across local and CI triggers
- per-issue isolated workspace lifecycle
- retry, continuation, and reconciliation scheduling
- restart-oriented recovery behavior
- structured status and evidence retention

Allowed future workflow contract scope:

- workspace hooks
- retry / cadence hints
- evidence retention and status metadata

Disallowed workflow contract scope:

- council math changes
- sovereignty changes
- approval-boundary rewrites

Important boundary:

- the unattended runtime substrate runs approved work
- the sovereign core still owns classification, topology, council aggregation, and `ok_to_execute`
- the unattended runtime substrate must not directly mutate issue state, labels, comments, or PR
  state except through Kernel-approved packets and gates

Initial validation harnesses should include:

- `scripts/sim-orchestrator-switch.sh` for lane and policy simulation
- `scripts/local/run-linked-systems.sh` for linked-system smoke/execute dispatch
- `scripts/sim-kernel-peripherals.sh` for cross-repo peripheral verification

## 5.3 Execution Node Topology

Kernel must define distinct host roles for `Mac mini` and `MBP` rather than treating both as
generic local machines.

Steady-state node responsibilities:

- `Mac mini` is the default primary execution node for unattended and long-running Kernel work
- `Mac mini` owns the always-on daemon or scheduler target, heavy tmux session residency, and
  local-first runtime artifacts
- on `Mac mini`, repo-context startup should minimize friction: bare `codex` may default to
  `kernel`, and `kernel` with no arguments should reopen the latest active run before falling back
  to guarded launch
- `MBP` is the attended operator workstation and full continuation node, not the steady-state
  always-on primary
- `MBP` must be able to inspect and continue a run through `doctor -> doctor --run -> recover-run`
  using repo state, shared secret plane, compact artifacts, and bounded recovery surfaces
- `MBP` may temporarily host heavy execution during migration, outage, or recovery, but that is an
  explicit degraded or transitional mode rather than the default architecture
- `cc pocket` remains degraded mobile continuation only
- `GitHub Actions` remains backup, audit, checkpoint mirror, and bounded external continuity only

Portability requirements:

- no run may depend on MBP-only hidden state to resume safely
- the same `kernel_run_id`, compact artifact, and recovery metadata must remain auditable across
  `Mac mini`, `MBP`, and `GitHub Actions`
- operator friction must stay low: MBP recovery should prefer direct `ssh` or `tmux` plus bounded
  `doctor` or `recover-run` flows over long local wrapper chains

## 6. Adaptive Lane Topology

The orchestrator must choose topology dynamically instead of using one fixed lane layout for every task.

### 6.1 Classification Output

The classifier must emit at least:

- `complexity_tier`: `small | medium | large | critical`
- `task_kind`: `read | review | implement | refactor | migration | incident`
- `domain_flags`: `ui`, `realtime`, `artifact`, `claude_adapter_needed`, `security_sensitive`
- `rollback_difficulty`: `low | medium | high`
- `external_side_effects`: `true | false`

### 6.2 Small Topology

Target use cases:
- one-file or few-file fixes
- clear bugfixes
- low-ambiguity tasks
- low rollback cost

Default topology for autonomous write tasks:

1. `gpt-5.4 main-orchestrator`
2. `spark-implementer`
3. `spark-critic`
4. `spark-verifier`
5. `claude-adapter-reviewer`
6. `glm-general-reviewer`

Policy:
- `spark x3` is the default fast path for small tasks.
- This keeps the system FUGUE-like by preserving multi-model review while using Codex multi-agent for speed.
- Read-only small tasks may waive Claude and shrink to a lighter topology.
- The default simulation and verification workers for small tasks should also be `spark x3`.

### 6.3 Medium Topology

Target use cases:
- multi-file implementation
- moderate coupling
- config or integration work
- non-trivial API changes

Default topology:

1. `gpt-5.4 main-orchestrator`
2. `spark-architect`
3. `spark-implementer`
4. `spark-critic`
5. `spark-verifier`
6. `claude-adapter-reviewer`
7. `glm-code-reviewer`
8. `glm-general-reviewer`

Optional:
- add `Gemini` when `ui=true`
- add `xAI` when `realtime=true`

### 6.4 Large Refactor / Migration Topology

Target use cases:
- large refactor
- rewrite
- migration
- cross-layer or cross-repo changes
- incident response with unclear failure modes

Default topology:

1. `gpt-5.4 main-orchestrator`
2. `spark-architect`
3. `spark-plan-reviewer`
4. `spark-implementer-a`
5. `spark-implementer-b`
6. `spark-critic`
7. `spark-reliability-engineer`
8. `claude-adapter-reviewer`
9. `glm-code-reviewer`
10. `glm-general-critic`
11. `glm-invariants-checker`
12. `glm-reliability-reviewer`

Conditional:
- add `Gemini` for UI/UX-heavy work
- add `xAI` for realtime/X-dependent work
- add `Manus` for artifact/research generation, but keep it non-voting by default

Large tasks must enforce:
- candidate A/B comparison
- failure-mode inventory
- rollback check
- verification evidence before merge

## 7. Promotion Rules

The orchestrator must promote a task to a larger topology when any of the following are true:

- changed files exceed the small-task threshold
- schema, migration, auth, billing, secrets, or infrastructure are touched
- ambiguity remains after initial proposal synthesis
- council disagreement is strong or persistent
- rollback difficulty is `high`
- a Claude-native peripheral workflow is required
- the task is labeled or detected as refactor / rewrite / migration / incident
- fast verification returns conflicting results
- a peripheral integration smoke test fails or times out

The orchestrator may demote a task only when:

- the write surface is narrow
- rollback is easy
- no external side effects occur
- no specialist lane is required

## 8. Council And Auto-Execution Policy

### 8.1 Baseline Council

For autonomous write execution, the default baseline council is:

- `Codex family`
- `GLM`
- `specialist x1`

`Claude` is strongly recommended when available and healthy, but it is not a required baseline
prerequisite for Kernel.

This preserves the original multi-voice safety intuition while matching the real continuity model:
Kernel often runs specifically when `Claude` is unavailable or rate-limited, so the minimum healthy
write shape must remain `Codex + GLM + specialist`.

### 8.2 Voting

Execution approval must use:

- weighted `2/3` consensus
- HIGH-risk veto
- successful participation from the baseline council for non-trivial writes

The orchestrator selects the final action after reviewing lane outputs. The council constrains and contests the orchestrator; it does not replace the orchestrator.

### 8.3 Auto-Execute Allowed

Auto-execute is allowed when:

- weighted vote passes
- no HIGH-risk finding exists
- baseline council participation is successful
- rollback path is present
- no human-consent gate is triggered

### 8.4 Human Approval Required

Human approval remains mandatory for:

- mass deletion
- destructive production operations
- secrets, auth, billing, or trust-boundary changes
- irreversible migrations
- high-impact external side effects without rollback

## 8.5 Verification Fabric

Kernel should separate `proposal speed` from `confidence speed`.

Default verification routing:

- `spark-first simulation`
  - Use `gpt-5.3-codex-spark` workers for fast smoke, topology checks, artifact linting, and dry-run evaluation.
- `promote on disagreement`
  - Escalate to `gpt-5.4 + Claude + GLM` council only when spark lanes disagree, fail, or detect risky coupling.
- `budget heavy peripherals`
  - Expensive integrations such as video rendering should not block every loop.
  - They should run as budgeted or sampled verification jobs unless the task directly targets that subsystem.

## 9. Claude Executor And Agent Teams Policy

`Claude` stays in the system, but as a bounded executor by default.

### 9.1 Allowed Roles

- `claude-adapter-reviewer`
- `claude-native workflow executor`
- `claude-teams-executor` for narrow exceptional scenarios

### 9.2 Agent Teams Unlock Policy

Claude Agent Teams may be re-enabled only under all of these conditions:

- main orchestrator remains `gpt-5.4`
- task is classified `large` or `critical`
- task explicitly benefits from real-time member-to-member collaboration
- Claude rate-limit state is healthy
- Codex multi-agent alone is judged insufficient

Initial guardrails:

- default `off`
- maximum `1` Agent Teams invocation per task
- small fixed member cap
- mandatory summary handoff back to the Codex council
- no direct ownership of issue state transitions

Recommended use cases:

- large codebase exploration with conflicting hypotheses
- cross-layer incident debugging
- Claude-native skill chains that materially benefit from direct member communication

### 9.3 Future Claude Main Compatibility

If `Claude main orchestrator` is ever restored, it should be restored only as:

- `claude-sovereign-compat`

This mode must:

- emit the same Kernel protocol objects as `codex-sovereign`
- preserve council math and risk gates
- preserve run trace schemas
- preserve peripheral dispatch contracts
- keep Claude-specific throttling and team limits inside the adapter, not in Kernel core

This keeps the architecture reversible without making Kernel Claude-coupled.

### 9.4 Re-switch To Legacy FUGUE

Kernel should preserve a typed rollback path to legacy FUGUE through:

- `fugue-bridge`

This bridge must:

- accept the same Kernel protocol packets up to the handoff boundary
- preserve council math and human-approval rules
- preserve peripheral dispatch contracts
- preserve run trace continuity so rollback remains auditable
- keep legacy-specific logic out of Kernel core

This makes `switch back to FUGUE` a supported adapter path rather than an implicit operational trick.

## 10. Peripheral Integration Contract

Peripheral power is a first-class requirement, not a side note.

The kernel must preserve or improve integration with:

- slide generation
- note manuscript workflows
- Obsidian pipelines
- video / Remotion pipelines
- Manus artifact generation
- notifications
- linked local systems
- protected Cursorvers business systems

Control rule:

- `gpt-5.4` decides when a peripheral system is needed
- Claude may execute the peripheral workflow
- results return to the council as artifacts, not as control-plane truth

Validation rule:

- every peripheral adapter must provide a cheap `smoke` or `dry-run` path
- linked-system orchestration must be testable with mocked issue providers
- adapters without cheap validation paths are not eligible for default always-on execution
- when a business-critical system lives in another repo/runtime, Kernel must validate against its existing contract instead of assuming local replacement
- peripherals should declare `authority`, `validation_mode`, `contract_owner`, and `preferred_lane` via the adapter manifest

## 10.1 Codex Plugin Packaging Boundary

OpenAI Codex plugins are acceptable for packaging reusable Kernel-adjacent capabilities, but they
must not become the authority for Kernel sovereignty.

Allowed plugin uses:

- distributing reusable `skills`, `.app.json` connector mappings, and `.mcp.json` server packs
- shipping cross-project operator helpers or readonly integration bundles through a repo or
  personal marketplace
- promoting stable, shared workflows after they have already proven out as repo-local assets

Disallowed plugin uses:

- replacing repo-local `AGENTS.md`, `CODEX.md`, or `.codex/prompts/kernel.md` as the authoritative
  Kernel contract
- owning council math, `ok_to_execute`, approval policy, runtime ledger, or compact artifact truth
- hiding required Kernel behavior behind a team-local plugin install that is absent from the repo

Policy:

- Kernel sovereignty remains repo-local and prompt-local
- plugins are a distribution layer for reusable adjuncts, not a substitute for repository-owned
  control-plane rules
- during active workflow iteration, prefer local skills and repo-owned docs first; promote to a
  plugin only when the behavior is stable enough to share across projects or teams

## 11. Model Policy Requirements

The new system must adopt `latest-first` model policy:

- `gpt-5.4` is the primary default orchestrator model
- `gpt-5.3-codex-spark` is the primary fast fan-out model
- `gpt-5-codex` is fallback only

Important current blocker:

- the existing model policy normalizes Codex main back to `gpt-5-codex`
- the next implementation must update normalization so `gpt-5.4` is accepted as the latest main kernel

## 12. Current Validation Observations

The current FUGUE codebase already demonstrates part of this target shape:

- `claude-light` reduces depth when Claude is main
- `codex-full` preserves richer multi-agent execution
- current matrix generation can already reach `18-19` lanes in Codex-centered topologies
- linked-systems orchestration can complete a mocked `smoke` run across all configured adapters with `5/5` success
- Cloudflare Discord regression checks currently pass `129/129`
- `cursorvers_line_free_dev` function suite currently passes `506` tests with `0` failures and `2` ignored
- Supabase and Vercel contracts are now verifiable through a single cross-repo harness

The current validation loop can be executed with:

- `scripts/sim-kernel-peripherals.sh`
- `scripts/check-peripheral-adapters.sh`
- `scripts/check-sovereign-adapters.sh`
- `scripts/sim-sovereign-adapter-switch.sh`

Current validation defects and readiness notes:

- `scripts/lib/mcp-rest-bridge.sh --smoke` had a JSON assembly bug on mixed success/failure paths
- `scripts/sim-orchestrator-switch.sh` assumed repo-root cwd instead of resolving paths from the script location
- `scripts/lib/model-policy.sh` now normalizes Codex main to `gpt-5.4`, with `gpt-5-codex` retained only as an explicit fallback
- `auto-video` smoke is materially heavier than the other linked systems and should be treated as budgeted verification
- Cursorvers LINE root-level reproducibility was previously broken and has now been repaired with repo-level Deno configuration

Therefore, the new system does not require inventing multi-lane governance from scratch. The main missing pieces are now:

- bounded Claude Agent Teams release policy
- explicit sovereign adapter promotion for future provider reversibility
- first-class adapters for Claude-session-only MCP surfaces
- productionized Codex Harness Core implementation behind the current validation scripts

## 13. Acceptance Criteria

1. `gpt-5.4` is accepted as the default main kernel model.
2. Small autonomous write tasks use `spark x3` fast topology by default.
3. Large refactor tasks auto-promote to `10+` lane topologies.
4. `Codex + GLM + specialist` baseline council remains the default autonomous write gate.
5. `Gemini` joins only when UI/UX flags are set.
6. `Claude Agent Teams` is supported only as a bounded executor lane, not as a second orchestrator.
7. Future `Claude main` remains possible only through a sovereign adapter contract, not through bespoke core branching.
8. The orchestrator chooses topology without requiring the user to manually classify every task.
9. Human approval is requested only for destructive or irreversible actions.
10. `Mac mini` and `MBP` responsibilities are explicit, with `Mac mini` as the default primary and
    `MBP` as the full continuation node.
11. A bounded `MBP` recovery path exists through `doctor -> doctor --run -> recover-run` without
    requiring MBP-only hidden runtime state.
12. Codex plugins are permitted only as reusable packaging for non-sovereign Kernel adjuncts and
    do not replace repo-local Kernel authority.

## 14. Rollout Direction

Phase 1:
- update model policy for `gpt-5.4`
- implement adaptive topology selection
- preserve existing council math

Phase 2:
- add explicit `small / medium / large / critical` routing
- wire small-task `spark x3` topology
- wire large-task promotion rules

Phase 3:
- add bounded `claude-teams-executor`
- integrate peripheral adapter contracts
- validate end-to-end autonomy with linked systems
