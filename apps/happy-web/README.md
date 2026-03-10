# Kernel Orchestration Surface

`Happy Web` now serves as the implementation codename for the mobile
`Kernel orchestration` surface.

The runtime-facing app name is `Kernel Orchestration`.

It is intentionally:

- mobile-first
- PWA-ready
- dependency-light
- separate from the desktop Codex workflow

This app is the outer shell. The inner conversational surface remains `Happy`.

## Structure

- `index.html`
- `styles.css`
- `manifest.webmanifest`
- `sw.js`
- `src/kernel-state.js`
- `src/adapters/`
- `src/domain/`
- `src/data/`
- `src/render.js`
- `src/app.js`
- `pencil-brief.md`
- `gemini-critique-prompt.md`
- `tests/`

## Scope

This app owns:

- `Happy`
- `Now`
- `Tasks`
- `Alerts`
- `Recover`

It does not replace:

- desktop Codex/terminal
- Cockpit deep-debug view
- GitHub Actions continuity/recovery
- FUGUE rollback path

## Adapter model

The first implementation slice now uses explicit adapters instead of wiring the
UI directly to a single state blob.

- `happy-app-intake`
  - packet normalization and composer contract
- `happy-app-state`
  - normalized mobile state and local cache
- `happy-app-crow`
  - short operational narratives for mobile use
- `happy-app-recovery`
  - bounded recovery actions over the shared recovery model
- `happy-event-protocol`
  - shared event, queue, and task-status vocabulary used across UI and adapters

These adapters are still backed by mock/local state so the UI stays portable and
testable. Remote mode now prefers an append-only event feed and only falls back
to snapshot hydration when an event cursor is not yet available.

The current seed is now `event-feed ready`.

- remote mode is the default runtime profile
- runtime config is read from HTML meta tags or `window.__HAPPY_RUNTIME_CONFIG__`
- if `remoteEnabled=true` and endpoints are configured, intake and recovery are
  written to a local queue first and synced later
- default remote endpoints are relative and co-located with the Worker:
  - `happy-events-endpoint=/api/happy/events`
  - `happy-intake-endpoint=/api/happy/intake`
  - `happy-recovery-endpoint=/api/happy/recovery`
  - `happy-task-detail-endpoint=/api/happy/task-detail`
- `happy-events-endpoint` is preferred for cursor-based remote event replay
- `happy-state-endpoint=/api/happy/state` provides bootstrap/snapshot fallback for cold starts
- `happy-task-detail-endpoint` can append task-specific detail events when a
  sheet is opened

## Design review helpers

- `pencil-brief.md`
  - visual/wireframe brief for Pencil.dev
- `gemini-critique-prompt.md`
  - critique prompt for Gemini CLI UI review

## Verification

```bash
bash /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-view-contract.sh
bash /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-state-contract.sh
bash /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-design-contract.sh
bash /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-pwa-shell.sh
node /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-behavior-contract.js
```
