# Kernel Vote Production Validation (2026-03-12)

## Summary

- branch: `kernel-vote-default-alignment`
- validated head: `c67705157f138bececc6417c1301824cad43ec29`
- objective: confirm that `kernel/vote` design intent is implemented and survives live GitHub Actions canary execution
- result: passed

## Verified Production Runs

- `fugue-matrix-parity`
  - run: `23004264651`
  - result: `success`
- `fugue-orchestration-gate`
  - run: `23004265180`
  - result: `success`
- `fugue-orchestrator-canary`
  - run: `23004283991`
  - mode: `lite`
  - result: `success`

## Verified Canary Outcomes

- regular issue: `#493`
  - evidence: `## Tutti Integrated Review`
  - result: `Canary pass (regular)`
  - cleanup: automatic close confirmed
- rollback issue: `#494`
  - evidence: `## Tutti Integrated Review`
  - result: `Canary pass (rollback)`
  - cleanup: automatic close confirmed

## What Was Required To Make This Green

- `fugue-orchestration-gate` now dispatches canary against the active branch ref during `workflow_dispatch` validation instead of hardwiring `main`.
- `fugue-orchestrator-canary` now accepts and forwards `trust_subject`.
- `run-canary.sh` now resolves trust from run metadata and dispatches `fugue-tutti-caller.yml` against the active branch ref.
- `fugue-tutti-router.yml` now honors explicit canary-owned dispatches with a bounded trust bypass instead of failing permission checks.

## Design-Intent Verdict

`kernel/vote` is materially realized in production:

- planning and implementation preserve multi-lane execution instead of collapsing to a single orchestrator
- baseline diversity remains `codex + claude + glm`
- implementation phase keeps `codex-multi-agent + GLM + bounded Claude teams`
- `/vote` continues as a local continuation contract, not a GitHub-only side effect
- integrated review and canary evidence are visible on the live issue path

## Remaining Work

No open work remains on this validation track. Future changes should preserve the same three-run proof:

- matrix parity green
- orchestration gate green
- live canary green on the branch under validation
