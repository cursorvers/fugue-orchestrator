# Kernel Unattended Runtime Substrate

## Goal

Define the minimum runtime substrate that `Kernel` should implement for long-running unattended
operation without weakening Kernel governance.

This document captures the `Symphony essence` that is worth absorbing into `Kernel`.

## Design Rule

`Kernel Sovereign Core` decides.

`Kernel Unattended Runtime Substrate` runs.

The runtime substrate is an execution and observability layer. It does not own control-plane
judgment.

## Scope

The runtime substrate should own:

- daemon lifecycle
- poll / refresh cadence
- issue eligibility refresh
- per-issue workspace allocation
- run continuation and retry scheduling
- stalled-run detection
- recovery-oriented status surfaces
- evidence retention for completed or interrupted runs

The runtime substrate should not own:

- topology policy
- quorum rules
- execution approval
- destructive action approval
- provider sovereignty

## Start Signal Arbitration

The runtime substrate must not invent a second execution start path for GitHub issues.

For the current repository shape:

- plain issue creation is intake only
- trusted execution start signals are `/vote`, explicit `tutti`, or direct `workflow_dispatch`
- unattended polling may operate on already-authorized work queues, already-claimed tasks, or a
  future dedicated Kernel queue
- unattended polling must not reinterpret raw `opened` issue events as implicit permission to start
  mainframe execution

## Core Components

### 1. Scheduler

Responsibilities:

- watch for dispatchable work from issue intake or queue state
- coalesce repeated refresh requests
- enforce bounded concurrency
- maintain claimed / running / retry-queued state
- prevent duplicate execution across local daemon, watchdog, and GitHub-triggered continuity flows

### 2. Reconciler

Responsibilities:

- refresh live issue state
- stop runs that became terminal or ineligible
- continue active work when the task remains eligible
- preserve explicit reasons for stop / retry / downgrade

### 3. Workspace Manager

Responsibilities:

- derive deterministic workspace keys from issue identifiers
- keep each run inside its assigned workspace root
- persist evidence and artifacts per run
- prevent workspace-local secrets from becoming the source of truth

### 4. Run Driver

Responsibilities:

- launch lane execution from Kernel-approved topology
- attach run metadata and trace ids
- collect receipts, logs, and evidence links
- emit structured completion / failure envelopes

### 5. Status Surface

Responsibilities:

- expose operator-visible status snapshots
- show running, retrying, degraded, and blocked work
- support recovery handoff between local primary and GitHub continuity

## Recommended Runtime State

The substrate should model at least:

- `claimed`
- `running`
- `retry_queued`
- `continuity_degraded`
- `awaiting_human`
- `terminal`

This state is scheduler state only. It is not a substitute for tracker state or Kernel decision
packets.

## Claim And Idempotency Contract

The substrate must treat duplicate scheduling as a correctness bug.

Required invariants:

- one active claim per issue / task identity
- claim records are deterministic and auditable
- repeated triggers coalesce instead of producing parallel duplicate execution
- restart recovery rebuilds claimable state without assuming an external database
- reconciliation can release stale claims safely

## Workflow Contract Boundary

Future unattended runs may use a repo-owned workflow contract similar to `WORKFLOW.md`, but the
contract must be bounded.

Allowed contract concerns:

- cadence and retry hints
- workspace hooks
- evidence retention policy
- adapter preparation hooks
- status-surface metadata

Disallowed contract concerns:

- quorum rewrite
- sovereignty rewrite
- approval-policy override beyond Kernel safety limits
- linked-system contract rewrites
- direct tracker mutation rules

## Topology Integration

The runtime substrate should consume:

- classification output
- topology request
- council packet requirements

It should then drive:

- workspace creation
- lane launch
- reconciliation loop
- trace and evidence persistence

The substrate may emit:

- runtime context
- retry reason
- reconciliation outcome
- workspace receipt

Those outputs enrich observability but do not override Kernel decision packets.

## Tracker Mutation Rule

The unattended runtime substrate must not directly change issue states, labels, comments, or PR
state as an independent authority.

If tracker or PR mutation occurs, it must happen through Kernel-approved decision flow and remain
visible in the same run trace.

## Continuity Model

Primary target:

- `mac mini` local daemon

Continuity target:

- `GitHub Actions` warm standby

Rollback target:

- `fugue-bridge`

The same run should remain auditable across all three paths via shared trace ids, evidence paths,
and normalized status summaries.

## Initial Implementation Slice

1. formalize scheduler state and run receipts
2. define deterministic per-issue workspace layout under Kernel-approved roots
3. add continuation / retry / reconciliation envelope types
4. wire status snapshots into recovery tooling
5. keep governance decisions in the sovereign core

## Verification

Before runtime promotion, require:

- sovereign adapter validation still green
- kernel peripheral simulation still green
- local daemon topology still consistent with standby and rollback docs
- restart / retry / reconciliation behavior documented in the recovery runbook
- duplicate-claim and out-of-root workspace launch behavior covered by dedicated substrate tests
