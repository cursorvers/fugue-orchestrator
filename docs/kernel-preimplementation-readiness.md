# Kernel Pre-Implementation Readiness

## Goal

Define the point at which `Kernel` can begin implementation as a credible replacement path for the legacy Claude orchestration plane without regressing governance, speed, or peripheral compatibility.

`Kernel` in this document means:

- legacy Claude-side lineage preserved
- `gpt-5.4` intended as the default future control-plane owner
- `Codex multi-agent` and `gpt-5.3-codex-spark` as the default speed engine
- `Claude` retained as executor / adapter / council participant by default, with future sovereign restoration possible only through a Kernel adapter

## What Must Be Preserved From The Legacy Claude Orchestration Plane

1. `Governance-first`
   - execution permission lives in orchestration, not in ad hoc scripts
2. `Baseline council`
   - default autonomous write gate remains `Codex + GLM + specialist`
   - `Claude` is recommended when healthy, but Kernel must remain executable without making Claude a hard prerequisite
3. `Risk-gated autonomy`
   - routine work proceeds through council approval
   - human approval is reserved for destructive, irreversible, or trust-boundary changes
4. `Evidence before done`
   - simulation, smoke, and regression evidence are required before claiming readiness
5. `Peripheral-first realism`
   - orchestration is not complete unless notifications, content systems, and protected business systems still work

## What Kernel Changes

1. `Single sovereign orchestrator`
   - no dual orchestrator or Claude-led control plane
2. `Adaptive topology`
   - small tasks use fast `spark x3`
   - larger tasks promote into wider councils and reliability lanes
3. `Codex Harness Core`
   - the old harness role moves under Codex ownership
   - simulation, runner resolution, continuity fallback, and artifact normalization become Codex responsibilities
4. `Protected contract integration`
   - business-critical systems can remain in separate repos and runtimes
   - Kernel orchestrates around them before attempting consolidation
5. `Provider reversibility`
   - future `Claude main` should remain possible through an adapter contract
   - reversibility must not leak provider-specific constraints back into Kernel core

## Peripheral Replacement Strategy

| Surface | Kernel role | Replacement stance |
|---|---|---|
| linked local systems | artifact / notification bus | retain and normalize |
| Discord | Cloudflare ingress + local notify lane | retain split architecture |
| LINE | protected cross-repo business platform | preserve as contract, do not absorb first |
| Supabase | first-class data/service adapter | standardize under Codex-owned adapter layer |
| Vercel | hosting / origin / deploy boundary | preserve as edge boundary, not orchestration authority |
| Manus | artifact / research engine | retain as non-voting worker |
| slide / note / Obsidian / video | specialist peripherals | keep behind smokeable adapters |

## Validation Completed

Validated in the current workspace:

1. Legacy Claude-side linked-system integrity check passes.
2. Legacy Claude-side orchestration simulation runs from script-relative paths.
3. Mocked linked-system smoke completes successfully across all configured adapters.
4. Cloudflare Discord regression subset passes `129/129`.
5. Cursorvers LINE full function suite passes `506` tests with `0` failures and `2` ignored.
6. Kernel cross-repo verification harness passes end to end:
   - `scripts/sim-kernel-peripherals.sh`
7. Sovereign reversibility contract is now machine-checkable:
   - `config/orchestration/sovereign-adapters.json`
   - `scripts/check-sovereign-adapters.sh`
   - `scripts/sim-sovereign-adapter-switch.sh`
   - `docs/kernel-fugue-migration-audit.md`
8. Peripheral systems are now modeled under an explicit adapter contract:
   - `docs/kernel-peripheral-adapter-contract.md`
   - `config/integrations/peripheral-adapters.json`
9. Claude-side policy regressions remain green:
   - `tests/test-model-policy.sh`
   - `tests/test-execution-profile-policy.sh`
   - `tests/test-workflow-risk-policy.sh`
   - `tests/test-orchestrator-policy.sh`

## What This Proves

1. The existing peripheral story is not fundamentally tied to a Claude-led control plane.
2. The strongest business-critical exception is `Cursorvers LINE`, and it can be validated as an external protected contract.
3. Kernel can preserve the current Discord/LINE/Supabase/Vercel shape without flattening everything into one runtime.
4. A PDCA-first verification loop can be made part of the product itself, not left as manual operator knowledge.
5. A future `Claude main` path can be supported without rebuilding the architecture if Kernel formalizes the sovereign adapter contract.
6. Re-switch to the legacy Claude-side path is now defined as an explicit bridge contract instead of an undocumented fallback.

## Remaining Blockers Before Real Implementation

1. `Claude Agent Teams` remains policy-only; bounded release logic is not yet wired.
2. Heavy peripherals such as `auto-video` still need budgeted verification policy rather than always-on loops.
3. Cockpit / Cloudflare control-plane contract still needs explicit Kernel naming and runtime ownership updates.
4. Sovereign adapter runtime promotion is incomplete:
   - `claude-sovereign-compat` remains contract-ready rather than production-promoted
   - Claude-session-only MCP surfaces still need first-class non-Claude adapters if Kernel is to own them directly
5. Unattended runtime substrate implementation is not yet promoted:
   - daemon scheduler / reconciliation / per-issue workspace behavior is now a fixed design target
   - production runtime state, receipts, and recovery surfaces still need implementation

## Implementation Entry Criteria

Kernel implementation should begin only when the following statement is true:

> The design is fixed, the preserved Claude-side doctrines are explicit, peripheral and business contracts are verified, and the remaining work is primarily control-plane implementation rather than discovery.

That condition is now substantially met.

## First Implementation Slice

1. Keep `gpt-5.4` as the default main kernel model across all workflow and runner entry points.
2. Expand the task-shape classifier only if a stronger workload classifier proves necessary beyond `small/medium/large/critical`.
3. Wrap existing linked-system dispatch under Codex-owned `Kernel` run metadata and trace ids.
4. Keep `Cursorvers LINE` external and validate it through the cross-repo harness on every PDCA cycle.
5. Promote `scripts/sim-kernel-peripherals.sh` from analysis tool to required preflight for Kernel rollout work.
6. Define `codex-sovereign` and `claude-sovereign-compat` against the same adapter interface before any future provider re-switch.
7. Keep `fugue-bridge` as the only allowed live rollback path before claiming runtime-perfect reversibility.
8. Implement the unattended runtime substrate as an execution layer under the sovereign core, not as a replacement for it.
9. Resume Google Workspace as a bounded adapter pilot through the readonly evidence lane first:
   - `docs/kernel-googleworkspace-integration-design.md`
   - `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
   - `docs/kernel-googleworkspace-implementation-todo.md`
