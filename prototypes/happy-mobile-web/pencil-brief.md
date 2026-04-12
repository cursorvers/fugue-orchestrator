# Pencil Brief

Design the outer all-in-one mobile app for `Kernel`.

Constraints:

- mobile-first
- iPhone-safe before Android-optimized
- one-handed use
- do not expose provider choice
- do not expose infrastructure sprawl
- `Happy.app` is the inner conversational pane inside the outer app

Screens:

1. `Happy`
2. `Now`
3. `Tasks`
4. `Alerts`
5. `Recover`

Must show:

- current route: `local`, `GHA continuity`, or `FUGUE rollback`
- current task and phase
- task output cards
- bounded recovery controls
- clear degraded/fallback state

Avoid:

- admin-dashboard density
- desktop table layouts
- fake precision progress indicators
- purple-on-white defaults
