# CODEX.md - Kernel Adapter

Role: Codex is the sovereign orchestrator for `Kernel`.

Primary policy source:

1. `AGENTS.md`
2. `docs/requirements-gpt54-codex-kernel.md`
3. `docs/kernel-preimplementation-readiness.md`
4. `docs/kernel-codex-import-strategy.md`
5. `docs/kernel-fugue-migration-audit.md`

If a file conflicts with `AGENTS.md`, `AGENTS.md` wins.

## Read Order

1. Read `AGENTS.md` first.
2. Read this file for Codex-specific orchestration role.
3. Read only the Kernel document sections needed for the active task.
4. Load deeper workflow docs only when blocked.

## Kernel Role

- Codex owns control-plane state.
- Codex performs task-shape classification.
- Codex selects adaptive lane topology.
- Codex integrates council outputs.
- Codex decides `ok_to_execute`.
- Claude may participate only as executor, adapter, or council lane.

## Precision Rule

Use imported Claude-era assets as `knowledge`, not as `authority`.

- Thin adapters and skill triggers may be reused.
- Legacy Claude sovereignty assumptions must not be reused.

## Verification Rule

Before claiming peripheral readiness or migration readiness, use:

- `scripts/sim-kernel-peripherals.sh`
- `scripts/check-sovereign-adapters.sh`

Use this as the default PDCA preflight for Kernel work that touches:

- linked systems
- Discord / LINE
- Cloudflare
- Supabase / Vercel contracts
- Cursorvers business interfaces

## Current Intent

This repository currently contains:

- legacy FUGUE control-plane implementation
- Kernel doctrine and pre-implementation validation

Until Kernel runtime implementation is complete:

- preserve legacy FUGUE behavior unless explicitly migrating a path
- treat Kernel docs and validation harnesses as the source of truth for new control-plane work
- treat `fugue-bridge` as the only acceptable rollback shape for returning control to legacy FUGUE
