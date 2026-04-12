# MCP Skill-CLI Migration (2026-03-07)

## Goal

Move MCP surfaces that no longer need session-bound transport into bounded
`skills + CLI` execution while preserving `FUGUE` fallback compatibility.

## Migrated

- `slack-session-mcp`
- `vercel-session-mcp`

These adapters now prefer:

1. `skill-cli`
2. `claude-session` fallback

## Kept Adapter-Backed

- `pencil-session-mcp`
- `excalidraw-session-mcp`

Reason:

- both still depend on session/runtime surfaces that are not improved by a fake
  CLI-only abstraction
- safe automation is still bounded to readiness or health probes

## Compatibility Rule

`Kernel` should prefer `skill-cli` when credentials or CLI support are
available.

If `skill-cli` is unavailable and a Claude session is active, the adapter may
fall back to `claude-session`.

This keeps:

- `Kernel` on a CLI-first path
- `FUGUE` rollback and Claude-attended continuity intact

## Verification

Validated on `2026-03-07`:

- `tests/test-mcp-adapter-policy.sh`
- `tests/test-mcp-adapter-exec.sh`
- `scripts/check-mcp-adapters.sh`
- `scripts/sim-kernel-peripherals.sh`
- production canary:
  - `cursorvers/fugue-orchestrator` run `22793439430` success
- latest production peripheral evidence:
  - `cursorvers/cursorvers_line_free_dev` `Manus Audit (Unified)` run
    `22793265594` success
  - `cloudflare-workers-hub` health endpoint returned `healthy`
- local attended/live evidence for remaining adapter-backed MCP:
  - `pencil-session-mcp` smoke returned `pencil adapter ready`
  - `excalidraw-session-mcp` smoke returned `excalidraw smoke passed`

## Non-Goals

- no change to Google Workspace adapter strategy while `gws` CLI rollout is in
  progress
- no attempt to force `Pencil` or `Excalidraw` into fake CLI-only flows
