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
3. In a fresh Codex session opened at this repository root, run `/kernel` before non-trivial work.
4. Read only the Kernel document sections needed for the active task.
5. Load deeper workflow docs only when blocked.

## Kernel Role

- Codex owns control-plane state.
- Codex performs task-shape classification.
- Codex selects adaptive lane topology.
- Codex integrates council outputs.
- Codex decides `ok_to_execute`.
- Claude may participate only as executor, adapter, or council lane.

## Slash Prompt Contract

- The supported entrypoint for Kernel work in this repository is a fresh Codex session started at the repository root and then `/kernel`.
- The authoritative prompt for this repository is `.codex/prompts/kernel.md`.
- Do not rely on `~/.codex/prompts/kernel.md` alone for repository work; treat the global prompt as convenience only.
- Hot reload is not guaranteed. After changing `.codex/prompts/kernel.md`, start a new Codex session before assuming the update is active.
- If `/kernel` is not recognized, restart Codex from this repository root and retry before doing manual fallback work.
- `/kernel` bootstrap must launch at least 2 active subagent lanes before the first acknowledgement.
- The first valid acknowledgement must include a `Lane manifest:` section describing currently active lanes, not planned lanes.

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

For `/kernel` prompt verification:

- static contract check: `bash tests/test-codex-kernel-prompt.sh`
- runtime smoke on a fresh session: `RUN_CODEX_KERNEL_SMOKE=1 bash tests/test-codex-kernel-prompt.sh`
- runtime smoke passes only when the acknowledgement includes both `Kernel orchestration is active ...` and a lane manifest with at least 2 active lanes

## Current Intent

This repository currently contains:

- legacy FUGUE control-plane implementation
- Kernel doctrine and pre-implementation validation

Until Kernel runtime implementation is complete:

- preserve legacy FUGUE behavior unless explicitly migrating a path
- treat Kernel docs and validation harnesses as the source of truth for new control-plane work
- treat `fugue-bridge` as the only acceptable rollback shape for returning control to legacy FUGUE
