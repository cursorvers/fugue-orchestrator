# Kernel Preflight Roadmap v1

## Objective

Turn the frozen requirements into a staged implementation plan that can run with minimal human interruption after the preflight gates are complete.

## Preflight Gates

1. Requirements freeze
2. Plan
3. Simulation
4. Critique
5. Replan
6. Execution

## Stage 0: Interface Freeze

Already frozen in:

- `docs/kernel/interfaces/schema-v1.md`
- `docs/kernel/interfaces/contracts.md`
- `docs/kernel/interfaces/track-compat.md`
- `docs/kernel/requirements-freeze-v1.md`
- `docs/kernel/requirements-phase-artifact-contract-v1.md`

No implementation track may change shared schemas without returning to replan.

## Stage 1A: Secret Plane

### Goal

Make local-first shared secrets work for Kernel without relying on repo `.env`.

### Scope

- canonical shared secret names
- shared bundle bootstrap into Keychain
- runtime resolver using `process env -> Keychain -> explicit external env file`
- GHA mirror as a secondary sink

### Done when

- canonical names are enforced consistently
- Keychain import matches canonical names
- runtime resolver works without repo `.env`
- GHA mirror consumes resolved env values without becoming truth

## Stage 1B: Runtime Evidence Enforcement

### Goal

Prevent phase completion from succeeding when required model evidence is missing.

### Scope

- phase-completion evidence gates
- provider usage evidence for codex / glm / specialist
- degraded mode evidence rules
- GLM recovery bookkeeping

### Done when

- requirements/plan/critique require `Codex + GLM + specialist`
- simulation requires `codex-spark`
- implementation/verification require `Codex + codex-subagent + GLM`
- UI/UX tasks require `gemini-cli` in addition
- Codex-only completion is rejected

## Stage 2: Auto-Compact

### Goal

Keep context pressure low by moving restart state into bounded artifacts.

### Scope

- compact artifact under `~/.config/kernel`
- max 3-line summary
- max 3 decisions
- exactly one executable `next_action` for restart
- additive `phase_artifacts` references only; no artifact body inlining
- explicit `kernel_run_id` caller boundary for workflow-side propagation
- workflow-side single-writer propagation only
- updates on `status_changed`, `phase_completed`, `run_completed`, and `manual_snapshot`

### Done when

- compact artifact is regenerated from runtime transitions
- summary remains bounded
- restart-critical fields are preserved
- required phase artifact references are visible without expanding execution context
- workflow-side propagation is no-op when `kernel_run_id` is absent or the compact artifact does not exist

## Stage 3: Doctor + tmux Handoff

### Goal

Allow MBP to resume the correct run quickly and safely.

### Scope

- `doctor` active-run listing
- `updated_at` descending sort
- standard list fields:
  - `project`
  - `purpose`
  - `tmux_session`
  - `phase`
  - `mode`
  - `next_action`
  - `updated_at`
- detail fields:
  - `run_id`
  - `active_models`
  - `blocking_reason`
  - `summary`
- stale detection
- session regeneration from compact artifact
- opt-in stale listing via `doctor --all-runs`
- bounded run detail via `doctor --run <run_id>`
- heavy-profile session regeneration via `recover-run <run_id>`

### Done when

- `doctor` lets an operator decide what to resume, where to attach, and what to do next
- stale runs are hidden by default
- missing sessions can be regenerated from compact state

## Stage 4: DR and Continuation

### Goal

Continue development when Mac mini is unavailable.

### Scope

- MBP as full continuation node
- cc pocket as degraded mobile continuation node
- GHA as audit/milestone marker only

### Done when

- MBP can continue using artifacts and secret plane
- cc pocket can inspect and continue lightweight work
- `run_completed` means verification finished, compact updated, and mirror dispatch finished
- the continuation path is documented in `docs/kernel/dr-continuation-runbook-v1.md`

## Parallelization Rules

### Safe parallel pair

- `Stage 1A: Secret Plane`
- `Stage 1B: Runtime Evidence Enforcement`

These may run in parallel because their write scopes are mostly disjoint after schema freeze.

### Dependent stages

- `Stage 2` depends on the runtime schema from `Stage 1B`
- `Stage 3` depends on the compact outputs from `Stage 2`
- `Stage 4` depends on `Stage 1A`, `Stage 2`, and `Stage 3`

## Known Risks From Preflight

1. Fixed specialist priority must not survive into runtime selection logic.
2. Canonical secret names must not drift from runtime mappings.
3. Runtime health cannot rely only on declared receipts; evidence should reflect actual provider use and freshness.
4. GLM degraded mode must not remain a mostly manual path.
5. `doctor` must remain a read-only restart surface, not a full control plane.

## Replan Decisions

1. `load-shared-secrets.sh doctor` becomes a preflight blocker for Kernel startup when required shared keys are missing.
2. Phase completion must block if required provider evidence is absent, even when bootstrap receipts exist.
3. `compact artifact` remains bounded by schema and is updated only on the frozen event set.
4. tmux session naming must use a shell-safe slug and auto-append `__short-id` on collision instead of relying on manual disambiguation.
5. Missing session recovery is treated as `run recovery`, not blind phase continuation:
   - restore `current_phase`
   - restore `mode`
   - restore `next_action`
   - restore `active_models`
   - restore `updated_at`
   - if required evidence is missing for that phase, restart from the phase entry instead of continuing blindly
