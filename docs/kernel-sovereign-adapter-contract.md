# Kernel Sovereign Adapter Contract

## Goal

Make `Kernel` reversible at the provider level without making the core architecture provider-coupled.

This contract allows:

- `codex-sovereign` as the default main orchestrator
- future `claude-sovereign-compat` if needed
- `fugue-bridge` when Kernel must hand control back to the legacy Claude orchestration plane

It avoids:

- bespoke dual-orchestrator branching
- provider-specific control-plane logic leaking into core
- reintroducing Claude rate-limit assumptions as architecture

## Core Principle

Kernel defines the orchestration protocol.

Providers do not define the protocol.

A provider becomes `main orchestrator` only by implementing the following contract.

## Required Adapter Interface

Each sovereign adapter must produce the same logical outputs:

1. `intake`
   - normalized task request
   - normalized user intent
   - trace id

2. `classification`
   - `complexity_tier`
   - `task_kind`
   - `domain_flags`
   - `rollback_difficulty`
   - `external_side_effects`

3. `topology_request`
   - selected lane topology
   - requested specialists
   - verification budget class

4. `council_packet`
   - proposal summary
   - candidate plans or diffs
   - risk inventory
   - required votes

5. `decision_packet`
   - vote summary
   - `ok_to_execute`
   - veto findings
   - rollback plan

6. `artifact_packet`
   - normalized outputs
   - evidence links
   - linked-system dispatch payloads

7. `fallback_packet`
   - degraded mode
   - fallback reason
   - provider health notes

## Governance Invariants

Every sovereign adapter must preserve:

1. weighted `2/3` council consensus
2. HIGH-risk veto
3. baseline council participation for non-trivial writes
4. human approval gates for destructive or irreversible actions
5. identical run trace and observability schema
6. identical linked-system dispatch contract

If an adapter cannot preserve these invariants, it is not a valid sovereign adapter.

## Unattended Runtime Boundary

`Kernel` may run on top of a separate unattended runtime substrate.

That substrate may own:

- scheduler cadence
- claim / idempotency bookkeeping
- work claiming
- retry / reconciliation
- per-issue workspace lifecycle
- status surfaces and recovery metadata

That substrate must not redefine:

- protocol packet semantics
- council aggregation
- `ok_to_execute`
- human approval boundaries
- tracker or PR state mutation policy

Runtime metadata may enrich the trace, but it is not a substitute for the sovereign adapter
interface.

## Default And Optional Adapters

### Default

- `codex-sovereign`

### Optional non-sovereign

- `claude-executor`
- `glm-reviewer`
- `gemini-ui-reviewer`

### Optional future sovereign

- `claude-sovereign-compat`

### Optional rollback bridge

- `fugue-bridge`

`fugue-bridge` is the explicit rollback adapter that maps Kernel protocol packets into the existing legacy Claude-side control plane.

## Claude-Specific Rule

If `claude-sovereign-compat` is implemented:

- Claude rate-limit handling stays inside the adapter
- Claude Agent Teams limits stay inside the adapter
- no Kernel core module should branch on `Claude` as architecture

This preserves reversibility without repeating legacy Claude-side coupling.

## Legacy Claude Bridge Rule

If `fugue-bridge` is activated:

- Kernel emits the same protocol packets up to the handoff boundary
- the bridge maps those packets into legacy Claude-side compatible inputs
- the legacy Claude-side path takes ownership only after the explicit handoff point
- council math and peripheral dispatch schema stay unchanged
- the rollback remains visible in the run trace

This keeps rollback to the legacy Claude-side path explicit, typed, and auditable.

## Migration Rule

During the Codex-first phase:

- keep Kernel defaulting to `codex-sovereign`
- keep Claude in executor/reviewer lanes
- develop future provider reversibility only against this contract
- route any rollback to the legacy Claude-side path through `fugue-bridge`, never through hidden branching

## Acceptance Test

A future sovereign adapter is acceptable only if:

1. the same input task yields the same protocol object structure
2. council aggregation is unchanged
3. peripheral dispatch surfaces remain unchanged
4. the existing Kernel verification harness still passes

In practice, this means:

- `scripts/sim-kernel-peripherals.sh` must remain green
- legacy governance regressions must remain green

## Manifest And Validation

Current machine-readable contract source:

- `config/orchestration/sovereign-adapters.json`

Current validation entry points:

- `scripts/check-sovereign-adapters.sh`
- `scripts/sim-sovereign-adapter-switch.sh`
- `scripts/sim-kernel-peripherals.sh`

These checks ensure:

1. `codex-sovereign` remains the default
2. `claude-sovereign-compat` remains contract-compatible
3. `fugue-bridge` remains rollback-compatible with the same packet schema
4. packet schema parity is preserved across sovereign adapters
5. governance invariants remain identical across sovereign adapters
