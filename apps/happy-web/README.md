# Happy Web

`Happy Web` is the first implementation seed of the outer all-in-one mobile
web app for `Kernel`.

It is intentionally:

- mobile-first
- PWA-ready
- dependency-light
- separate from the desktop Codex workflow

This app is the outer shell. The inner conversational surface is `Happy`.

## Structure

- `index.html`
- `styles.css`
- `manifest.webmanifest`
- `sw.js`
- `src/kernel-state.js`
- `src/adapters/`
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

These adapters are still backed by mock/local state so the UI stays portable and
testable. The next implementation step is to replace the adapter internals with
real endpoints without rewriting screen logic.

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
