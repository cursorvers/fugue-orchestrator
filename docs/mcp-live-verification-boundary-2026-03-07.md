# MCP Live Verification Boundary (2026-03-07)

Purpose:

- define what `Kernel` can verify automatically for session-backed MCP adapters
- separate `safe live smoke` from `manual/operator-attended verify`

## Verified Automatically Today

- `supabase-rest-mcp`
  - route: `rest-bridge`
  - status: safe live smoke / contract verified
- `stripe-rest-mcp`
  - route: `rest-bridge`
  - status: safe live smoke / contract verified
- `pencil-session-mcp`
  - route: `kernel-adapter`
  - status: safe readiness probe + local live readiness verified
  - automatic check:
    - wrapper resolved
    - local `Pencil` listen port detection if app is running
- `excalidraw-session-mcp`
  - route: `kernel-adapter`
  - status: safe health / import-export-clear smoke
  - automatic check:
    - healthcheck script
    - export/import/clear dry-run or local smoke against explicit server URL
- `slack-session-mcp`
  - route: `skill-cli` or `claude-session`
  - status: safe auth/webhook smoke only
  - automatic check:
    - `auth.test`
    - webhook delivery or `chat.postMessage`
- `vercel-session-mcp`
  - route: `skill-cli`
  - status: safe identity/list-projects smoke only
  - automatic check:
    - `whoami`
    - project listing

## Not Auto-Verified End-to-End

- actual Pencil editing session
- Excalidraw collaborative/manual canvas workflows
- Slack production-channel side effects beyond controlled smoke
- Vercel deploy / rollback side effects

Reason:

- these require operator intent or can create irreversible/noisy side effects
- safe automation should stop at readiness, auth, and non-destructive probes

## Operational Rule

1. automatic verification may use:
   - readiness probes
   - auth probes
   - dry-run
   - non-destructive smoke
2. end-to-end side effects require:
   - operator-attended run
   - or a dedicated canary environment

## Current Recommendation

- keep `pencil`, `slack`, `vercel` in `safe live smoke + contract` mode
- treat full end-to-end session validation as a separate attended verification track
- do not regress to `claude-session` by default when `skill-cli` or `kernel-adapter` is healthy

## Live Evidence (2026-03-07)

- `pencil-session-mcp`
  - local app launched
  - adapter smoke returned `pencil adapter ready`
  - detected WebSocket port: `55088`
- `excalidraw-session-mcp`
  - local live smoke returned `excalidraw smoke passed`
  - auto-detected server URL: `http://localhost:3001`
  - note: `localhost:3000` was occupied by another local app and is no longer the
    preferred default for the adapter
