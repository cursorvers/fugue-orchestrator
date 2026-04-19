# Kernel Requirements Freeze v1

## Goal

Build a high-quality, low-touch development system where, after requirements are frozen, work generally proceeds to completion without routine human intervention.

## Non-goals

- Do not modify or rely on FUGUE / Claude orchestration runtime behavior.
- Do not break legacy FUGUE compatibility identifiers or runtime contracts.
- Do not make GitHub Actions the main execution substrate.

## Completion Definition

Kernel is complete for this refactor when it provides an artifact-first development system that, after requirements freeze, generally runs to completion without routine stops and can be continued from Mac mini, MBP, and cc pocket.

この `requirements freeze v1` において、specialized requirement として参照する
`docs/kernel/requirements-phase-artifact-contract-v1.md` は `v1 frozen` として扱う。
その v2 候補は deferred であり、v1 完了判定を妨げない。

## Stop Conditions

Execution may stop only for:

- destructive actions
- external authentication or approval that cannot be satisfied by existing local evidence or
  non-critical council consensus
- major new facts that contradict frozen requirements

Non-critical work must proceed under Kernel council consensus by default. A `claude` orchestrator,
`codex` orchestrator, or local adapter must not ask the user for a second routine approval after
`ok_to_execute=true` and approved consensus evidence exist for the current run. Critical,
destructive, irreversible, secrets/auth/billing/trust-boundary, or materially ambiguous actions
remain human-gated.

## Execution Nodes

- `Mac mini`: primary execution node
- `MBP`: full continuation node via `tmux`
- `cc pocket`: mobile degraded continuation node via CLI
- `GHA`: backup, audit, milestone marker, and external mirror only

Execution-node requirements:

- `Mac mini` is the steady-state always-on host for unattended Kernel runs, heavy tmux residency,
  and local-first runtime artifacts
- on `Mac mini`, `kernel` with no arguments should reopen the latest active run before guarded
  launch when a healthy run already exists
- `MBP` is the attended operator and full continuation node; its default path is bounded recovery
  and continuation, not steady-state primary ownership
- `MBP` continuation must work via repo state, shared secret plane, compact artifact, `doctor`,
  and `recover-run` without depending on MBP-only hidden state
- `cc pocket` may inspect and continue degraded work, but does not replace `MBP` or `Mac mini`

`GHA` は primary state owner ではない。
ただし、明示的な `kernel_run_id` が渡され、既存 compact artifact が存在する場合に限り、
bounded な `phase_artifacts` path reference を milestone marker として追記してよい。
この許可は run 生成、run id 推測、primary state mutation を含まない。

## Kernel Run Model

- `1 request = 1 Kernel run`
- `1 tmux session = 1 Kernel run`
- same project may have multiple concurrent runs
- logical handoff label is `project:purpose`
- physical tmux session slug defaults to `project__purpose`
- if needed to avoid collision, append `__short-id`
- `purpose` is mandatory during requirements definition, provided by the human, then normalized by the system
- `purpose` is fixed for the run; if it changes materially, create a new run

## Phase Model Requirements

### Requirements / Plan / Critique

- normal shape: `Codex latest + GLM + specialist 1`
- GLM is preferred
- if GLM is unavailable, substitute with a specialist while GLM recovery proceeds in parallel
- specialist is chosen by the healthiest available free tier, with no fixed provider priority

### Simulation

- `codex-spark` only
- if `codex-spark` is unavailable, ask the user before substituting `codex-subagent`

### Implementation / Verification

- normal shape: `Codex latest + codex-subagent + GLM`
- if the task includes design or UI/UX, `gemini-cli` is additionally required

## Evidence Rule

- required model evidence is enforced at each phase-completion gate
- runtime should not treat Codex-only execution as phase-complete where multi-model evidence is required
- portable phase artifact visibility/validation requirements are defined separately in `docs/kernel/requirements-phase-artifact-contract-v1.md`

## Mandatory Gates

Every substantial run must pass:

1. requirements
2. plan
3. simulation
4. critique
5. replan
6. execution

## Secret Plane

- runtime `.env` in repo is not used as the live secret plane
- shared truth is an encrypted shared bundle
- current physical bundle remains `secrets/fugue-secrets.enc`
- conceptually this is the shared secret bundle, not a Kernel-owned name
- local runtime uses `process env -> Keychain -> explicit external env file`
- GHA receives a mirror only

## Plugin Packaging Boundary

- OpenAI Codex plugins may package reusable `skills`, app mappings, or MCP server bundles for
  Kernel-adjacent workflows
- plugins must not replace repo-local `AGENTS.md`, `CODEX.md`, or `.codex/prompts/kernel.md` as
  the Kernel source of truth
- plugins must not own council math, approval policy, runtime ledger, compact artifact truth, or
  `ok_to_execute`
- prefer repo-local assets while a workflow is still evolving; promote it into a plugin only after
  the behavior is stable enough to share across projects or teams

## State and Compact

- `bootstrap receipt`: startup contract
- `runtime ledger`: mutable run state
- `compact artifact`: compressed handoff state
- `doctor`: read-only display surface
- phase artifact handoff uses the specialized contract in `docs/kernel/requirements-phase-artifact-contract-v1.md`

### Compact Limits

- `summary`: max 3 lines
- `decisions`: max 3 items
- `next_action`: exactly one executable action for restart purposes

## Status Model

### States

- `healthy`
- `degraded`
- `blocked`

### Events

- `status_changed`
- `recovered`
- `phase_completed`
- `run_completed`
- `manual_snapshot`

### run_completed

`run_completed` means:

- verification finished
- compact updated
- mirror dispatch finished

## tmux Handoff

### Standard doctor list

Active runs only, sorted by `updated_at` descending, with:

- `project`
- `purpose`
- `tmux_session`
- `phase`
- `mode`
- `next_action`
- `updated_at`

### doctor detail

- `run_id`
- `active_models`
- `blocking_reason`
- `summary` (max 3 lines)

Detailed run inspection is opt-in by `run_id`.

### stale run

A run is stale when:

- its tmux session no longer exists, or
- it has not updated for 24 hours

Stale runs are hidden by default and shown only on request.

### Restart model

- if the tmux session still exists, resume by attach
- if the session is missing, treat it as stale and regenerate a new session from compact state
- regenerated session uses the recorded `phase`, `mode`, `next_action`, and default profile
- phase is carried forward, but execution resumes only if required evidence for that phase is present; otherwise restart from the phase entry
- `doctor --all-runs` may surface stale runs for manual inspection
- `doctor --run <run_id>` provides the bounded restart detail surface
- `recover-run <run_id>` regenerates the heavy-profile session for stale runs
- the MBP / cc pocket continuation path is documented in `docs/kernel/dr-continuation-runbook-v1.md`

## Window Profile

- default profile is `heavy`
- heavy windows:
  - `main`
  - `logs`
  - `review`
  - `ops`
- `light` is allowed only for short-lived runs

## Disaster Recovery

- Mac mini is primary, but not the only memory store
- MBP must be able to continue development if Mac mini fails
- `cc pocket` is a degraded continuation node, not a full replacement
- success means work can continue from artifacts and runtime state, not that tmux internals are perfectly restored
