# Kernel Interface Contracts

## Goal

Freeze the behavioral rules that sit on top of the shared schemas in `schema-v1.md`.

## 1. Event Contract

### State

- `healthy`
- `degraded`
- `blocked`

### Events

- `status_changed`
- `recovered`
- `phase_completed`
- `run_completed`
- `manual_snapshot`

### Rules

- `recovered` is an event, not a steady state.
- `run_completed` means:
  - verification finished
  - compact artifact updated
  - mirror dispatch finished

## 2. Gate Contract

Implementation starts only after these gates pass:

1. `Requirements Gate`
2. `Plan Gate`
3. `Simulation Gate`
4. `Critique Gate`
5. `Replan Gate`

Only then may work enter `Execution Gate`.

## 3. Evidence Contract

### Requirements / Plan / Critique

Normal shape:

- `Codex latest`
- `GLM`
- `specialist x1`

`Claude` is recommended when healthy, but not required for the Kernel minimum.

If `GLM` fails:

- `specialist` substitutes
- `GLM recovery` proceeds in parallel

### Simulation

- `codex-spark only`
- if unavailable, `codex-subagent` substitution requires explicit human approval

### Implementation / Verification

Normal shape:

- `Codex latest`
- `codex-subagent`
- `GLM`

If the task includes `design` or `UI/UX`:

- `gemini-cli` is additionally required

## 4. Auto-Compact Contract

Auto-compact updates only on:

- `status_changed`
- `phase_completed`
- `run_completed`
- `manual_snapshot`

Do not update compact artifacts on every minor runtime mutation.

## 5. DR Contract

Primary target:

- `Mac mini` is the primary execution node

Fallback target:

- `MBP` must be able to resume `Kernel degraded mode`

Success criterion:

- resume one critical run within 15 minutes using:
  - repo state
  - shared secret plane
  - compact artifact
  - doctor view
  - `doctor -> doctor --run -> recover-run`
