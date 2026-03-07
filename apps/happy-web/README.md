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
- `src/render.js`
- `src/app.js`
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

## Verification

```bash
bash /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-view-contract.sh
bash /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-state-contract.sh
bash /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-pwa-shell.sh
node /Users/masayuki/Dev/fugue-orchestrator/apps/happy-web/tests/test-behavior-contract.js
```
