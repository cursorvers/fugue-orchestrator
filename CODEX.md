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
- `/k` is a local one-word alias for `/kernel` in this repository and must obey the same Kernel bootstrap contract.
- The authoritative prompt for this repository is `.codex/prompts/kernel.md`.
- The local alias prompt for one-word chat-box startup is `.codex/prompts/k.md`.
- Do not rely on `~/.codex/prompts/kernel.md` alone for repository work; treat the global prompt as convenience only.
- Hot reload is not guaranteed. After changing `.codex/prompts/kernel.md`, start a new Codex session before assuming the update is active.
- If `/kernel` is not recognized, restart Codex from this repository root and retry before doing manual fallback work.
- Bare `/kernel` inside the Codex chat UI is not a local SLO path for this repository; it remains upstream Codex CLI/TUI behavior until proven otherwise.
- `/kernel` bootstrap must launch at least 6 active subagent lanes before the first acknowledgement.
- The minimum operating target is 6 or more concurrent lanes across multiple LLM models or model profiles.
- The first valid acknowledgement must include a `Lane manifest:` section describing currently active lanes, not planned lanes.
- The first valid acknowledgement must also include `Bootstrap target: 6+ lanes (minimum 6).`
- `/vote` and `/v` are local continuation prompts in this repository. They must not post to GitHub or hand off to issue-comment workflows.
- GitHub `/vote` workflow triggering remains an explicit issue-comment path (`gh issue comment ... --body '/vote'` or `vote-gh ...`), not a Codex slash prompt.
- Hot reload is not guaranteed for `.codex/prompts/vote.md` and `.codex/prompts/v.md` either. Restart the session after changing them.

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
- runtime smoke passes only when the acknowledgement includes `Kernel orchestration is active ...`, `Bootstrap target: 6+ lanes (minimum 6).`, and a lane manifest with at least 6 active lanes

For `/vote` prompt verification:

- static contract check: `bash tests/test-codex-vote-prompt.sh`
- runtime smoke on a fresh session: `RUN_CODEX_VOTE_SMOKE=1 bash tests/test-codex-vote-prompt.sh`
- runtime smoke passes only when output includes `Local consensus mode is active.`, `Smoke verification: PASS`, and `Smoke result marker: ...` within `CODEX_VOTE_SMOKE_TIMEOUT_SEC` seconds (default: `90`)
- CI static enforcement: `.github/workflows/fugue-orchestration-gate.yml` runs `bash tests/test-codex-vote-prompt.sh`
- approval-prompt quiescence rule applies to `/vote` and `/v`
- do not request approval for exploratory convenience; require explicit user ask or strict necessity first

Approval-prompt safety rules for `/kernel` and `/vote`:

- do not request approval for exploratory convenience
- Only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required
- quiesce active lanes that can still write to the current TTY before any approval prompt
- Do not surface approval prompts while background Codex activity is still emitting output into the same terminal.
- if quiescence cannot be established promptly, fail closed with a one-line `quiescence_timeout` status

## Current Intent

This repository currently contains:

- legacy FUGUE control-plane implementation
- Kernel doctrine and pre-implementation validation

Until Kernel runtime implementation is complete:

- preserve legacy FUGUE behavior unless explicitly migrating a path
- treat Kernel docs and validation harnesses as the source of truth for new control-plane work
- treat `fugue-bridge` as the only acceptable rollback shape for returning control to legacy FUGUE
