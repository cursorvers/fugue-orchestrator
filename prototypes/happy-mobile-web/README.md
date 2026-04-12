# Happy Mobile Web Prototype

This prototype is the outer all-in-one mobile web app for `Kernel`.

It is intentionally:

- mobile-first
- dependency-light
- PWA-ready
- implementation-facing, not final production UI

The inner conversational surface is represented as the `Happy` tab.

The prototype exists to validate:

- one-front mobile IA
- `Happy / Now / Tasks / Alerts / Recover`
- `Kernel / GHA continuity / FUGUE rollback` state transitions
- output visibility on mobile
- bounded recovery controls

## Files

- `index.html`
- `styles.css`
- `app.js`
- `manifest.webmanifest`
- `sw.js`
- `pencil-brief.md`
- `gemini-critique-prompt.md`

## Local open

Open `index.html` in a browser or serve it with any static file server.

## Simulation checks

Run:

```bash
bash /Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web/tests/test-view-contract.sh
bash /Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web/tests/test-state-model.sh
bash /Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web/tests/test-pwa-shell.sh
node /Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web/tests/test-behavior-contract.js
```
