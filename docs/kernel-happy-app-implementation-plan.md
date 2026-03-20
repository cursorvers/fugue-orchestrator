# Plan

Build the outer all-in-one mobile web app with `Happy.app` as the inner conversational surface, while keeping `Kernel` sovereign routing, `GHA` continuity, and legacy Claude-side rollback unchanged behind it. The approach is to ship a narrow mobile-first slice first, prove that progress and outputs are visible without exposing infrastructure sprawl, then widen the surface only after the shared state adapters are stable.

## Scope
- In: mobile web/PWA front, `Happy` conversational tab, `Now/Tasks/Alerts/Recover`, normalized task/output state adapters, bounded recovery controls
- Out: desktop replacement, `Cockpit` replacement, `GWS` integration work, native-first mobile shells

## Action items
[x] Create the outer mobile app skeleton and route structure for `Happy`, `Now`, `Tasks`, `Alerts`, and `Recover`
[x] Implement the `Happy` conversational surface and intake composer against a `happy-app-intake` adapter
[x] Implement `Now` and `Tasks` views against a normalized `happy-app-state` adapter with canonical output cards
[x] Implement task detail sheets and `Recover` controls over bounded `kernel-recovery-console` actions
[x] Add a `Crow` summarization adapter that converts workflow/issue/task state into short mobile narratives
[x] Add a mobile design contract plus `Pencil.dev` and `gemini-cli` review briefs to the implementation seed
[x] Define a `Kernel context governor` that keeps mobile and council payloads below reliability-risk bands
[x] Add `local-first / remote-ready` runtime config and endpoint adapter seams to `happy-web`
[ ] Verify the design contract with at least three parallel simulation lanes on every design-affecting change
[ ] Run production-like smoke checks for progress visibility, output visibility, and recovery actions before any live cutover
[ ] Keep legacy Claude-side rollback and `GHA` continuity paths visible in the state model but secondary in the mobile UX

## Prototype seed

The current implementation seed lives at:

- `/Users/masayuki/Dev/fugue-orchestrator/apps/happy-web`

The architecture prototype remains at:

- `/Users/masayuki/Dev/fugue-orchestrator/prototypes/happy-mobile-web`

Role split:

- `apps/happy-web`
  - implementation seed
  - app structure, modules, and testable contracts
- `prototypes/happy-mobile-web`
  - design/IA reference
  - architecture-facing fixture

Linked governor spec:

- [kernel-context-governor.md](./kernel-context-governor.md)

## Open questions
- Should the first slice live beside `cockpit-pwa` in the same repo or as a separate front-end package?
- Which authentication boundary should the mobile app use first: existing Cockpit auth or a narrower task-status token flow?
- Should `Happy` be the default landing tab, or should `Now` be the first screen after the very first task is created?
