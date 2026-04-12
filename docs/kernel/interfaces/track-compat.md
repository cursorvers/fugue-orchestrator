# Kernel Track Compatibility Map

## Goal

Define write scopes and collision boundaries so large refactor work can proceed in parallel where possible.

## Track A: Secret Plane

### Writes

- `scripts/sops/import-to-keychain.sh`
- `scripts/lib/load-shared-secrets.sh`
- `scripts/local/sync-gh-secrets-from-env.sh`
- `rules/secrets-management.md`
- `docs/kernel-fugue-secret-plane.md`

### Reads

- canonical secret schema
- org secret audit config

### Must not redefine

- runtime ledger fields
- compact artifact fields
- doctor display contract

## Track B: Runtime Enforcement

### Writes

- `scripts/lib/kernel-bootstrap-receipt.sh`
- `scripts/lib/kernel-runtime-ledger.sh`
- `scripts/lib/kernel-runtime-health.sh`
- provider execution wrappers
- tests for evidence enforcement

### Reads

- bootstrap receipt schema
- runtime ledger schema
- event contract

### Must not redefine

- secret resolution order
- compact artifact hard limits

## Track C: Auto-Compact

### Writes

- `scripts/lib/kernel-compact-artifact.sh`
- `bin/codex-kernel-guard`
- compact tests

### Reads

- runtime ledger schema
- bootstrap receipt schema
- compact schema
- doctor view schema

### Must not redefine

- runtime state meanings
- event names

## Track D: Doctor / Handoff / DR

### Writes

- `bin/codex-kernel-guard`
- handoff tests
- DR docs

### Reads

- receipt schema
- ledger schema
- compact schema
- handoff contract

### Must not redefine

- canonical secret schema
- required model evidence schema

## Parallelization Rule

Parallel implementation is allowed only after:

1. `schema-v1.md` is accepted
2. `contracts.md` is accepted
3. each track stays inside its write scope

If a change crosses schemas, it must return to `Replan Gate` before implementation continues.

