# ADR-002: Kernel Absorbs Symphony-Like Unattended Runtime Primitives

**Status**: Accepted
**Date**: 2026-03-08
**Deciders**: Kernel maintainers

## Context

`Kernel` is already aimed at long-running unattended operation on a dedicated primary host.
Existing design documents define:

- a Codex-first sovereign control plane
- a reversible sovereign adapter contract
- a local daemon + warm-standby topology

What is still under-specified is the runtime substrate between issue intake and lane execution.

`OpenAI Symphony` is relevant here because its draft specification isolates a useful subset of
runtime behavior:

- long-running daemon scheduling
- tracker polling and bounded dispatch
- per-issue isolated workspaces
- retry / reconciliation / restart recovery
- repository-owned workflow/runtime contract

Those elements are useful to `Kernel`, but Symphony's role as a scheduler/runner must not replace
Kernel governance.

## Decision

`Kernel` will absorb only the unattended runtime primitives that strengthen continuous autonomous
operation.

`Kernel` will not adopt Symphony as the control plane.

The adopted shape is:

- `Kernel Sovereign Core`
  - owns classification, topology, council aggregation, `ok_to_execute`, and final reporting
- `Kernel Unattended Runtime Substrate`
  - owns daemon scheduling, polling, workspace lifecycle, retry, reconciliation, and operator
    observability

## Adopted Primitives

1. `daemon scheduler`
   - fixed-cadence poll loop or equivalent event-driven refresh
2. `per-issue workspace isolation`
   - one workspace identity per issue / task run
3. `reconciliation`
   - stop, continue, or downgrade runs when issue state changes
4. `retry / continuation`
   - bounded backoff with explicit audit trail
5. `repo-owned workflow contract`
   - future runs read versioned runtime policy from the repository
6. `structured observability`
   - run trace, evidence paths, state snapshots, and recovery visibility

## Explicit Non-Adoption

The following remain `Kernel` responsibilities and are not delegated to the unattended runtime
substrate:

- sovereign adapter semantics
- provider selection doctrine
- council membership rules
- weighted `2/3` consensus
- HIGH-risk veto
- human approval boundaries
- linked-system dispatch contract

## Consequences

### Positive

- unattended execution becomes a first-class design target instead of an implied operator pattern
- local daemon, self-hosted runner, and GitHub continuity can share one runtime model
- per-issue workspace hygiene becomes explicit
- restart recovery and recovery runbooks become easier to reason about

### Negative

- more runtime state must be modeled and observed
- repo-owned workflow contracts can become a second policy plane if not kept bounded
- poorly-scoped polling could duplicate existing issue-router behavior

## Guardrails

1. runtime substrate must remain subordinate to `Kernel Sovereign Core`
2. any workflow contract must not redefine governance invariants
3. runtime packets may enrich observability and scheduling only
4. `fugue-bridge` remains the only rollback path to legacy control-plane ownership

## Acceptance Criteria

1. unattended runtime can start, stop, retry, and reconcile runs without changing council math
2. per-issue workspaces remain auditable and bounded to approved roots
3. run traces remain schema-compatible across local primary, standby continuity, and rollback paths
4. verification harnesses for sovereign adapters and kernel peripherals remain green
