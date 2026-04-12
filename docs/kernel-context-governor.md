# Kernel Context Governor

This document defines the context-governance rules for `Kernel` under the
working assumption that `gpt-5.4` becomes materially less reliable when active
working context grows too large.

The purpose of this spec is not to guess an official hard limit. It is to make
`Kernel` robust even if quality decays before the advertised context window is
fully consumed.

## 1. Design stance

`Kernel` must behave as if:

- large context is expensive
- large context is noisy
- large context should be treated as a risk signal
- raw accumulation is worse than structured retrieval

Therefore:

- `Kernel` never treats the full window as a target
- `Kernel` prefers compact state packets over long transcripts
- `Kernel` splits, summarizes, and retrieves instead of piling on history
- legacy Claude-side compatibility must survive the same compression rules

## 2. Budget bands

The system should use soft bands, not a single hard cap.

- `green`
  - up to `40K`
  - normal operation
- `amber`
  - `40K-80K`
  - summaries preferred, large artifacts referenced not inlined
- `red`
  - `80K-100K`
  - mandatory compression, lane payload reduction, retrieval only for details
- `hard-stop`
  - over `100K`
  - no further accumulation
  - split task or restart from compressed state packet

These bands are intentionally conservative.

## 3. Canonical packet model

All long-running flows should compress into a small number of packet types.

- `task-summary`
  - intent
  - current phase
  - blockers
  - next action
  - target size: `<= 2K`
- `decision-summary`
  - decision
  - evidence
  - risk
  - rollback note
  - target size: `<= 2K`
- `run-summary`
  - active lane
  - outputs
  - current errors
  - target size: `<= 3K`
- `repo-summary`
  - touched files
  - key invariants
  - test evidence
  - target size: `<= 4K`
- `mobile-status-summary`
  - healthy/degraded/fallback
  - phase
  - last output
  - human-needed flag
  - target size: `<= 1K`

Raw logs, huge diffs, and prior chat turns must be referenced by path, run id,
or artifact id instead of inlined.

## 4. Lane budgets

Different lanes should receive different context sizes.

- `codex-main`
  - preferred: `<= 48K`
  - emergency ceiling: `72K`
- `claude-reviewer`
  - preferred: `<= 24K`
  - emergency ceiling: `40K`
- `glm-reviewer`
  - preferred: `<= 20K`
  - emergency ceiling: `32K`
- `gemini-ui`
  - preferred: `<= 16K`
  - emergency ceiling: `24K`
- `mobile-crow`
  - preferred: `<= 4K`
  - emergency ceiling: `8K`

No lane should receive the entire accumulated system transcript by default.

## 5. Compression triggers

Compression should occur on any of these conditions.

- active prompt enters `amber`
- more than `3` major artifacts are attached
- more than `2` task pivots occurred in the same thread
- a single diff exceeds the lane budget
- mobile status generation would exceed `4K`
- a retry or fallback is about to inherit prior turns wholesale

When triggered:

1. compress current state into canonical packets
2. replace raw history with references
3. restart the active lane from the compressed packet set

## 6. Retrieval rules

Retrieval is allowed only for the specific detail currently needed.

- retrieve one artifact, not all artifacts
- retrieve one file cluster, not the entire repo diff
- retrieve one prior decision packet, not the whole debate
- retrieve one output card, not the entire timeline

This prevents summary drift from becoming summary bloat.

## 7. Mobile rules

`Happy` and the outer mobile app must never carry heavy context.

- mobile surfaces consume `mobile-status-summary`
- `Tasks` shows only compact task cards
- task detail expands from canonical outputs, not raw logs
- `Recover` shows bounded actions only
- if a user requests deeper detail, the system returns a short summary plus a
  link to deeper evidence

## 8. Legacy Claude-side compatibility

The context governor must not make legacy Claude-side rollback impossible.

Therefore:

- `handoff_target=fugue-bridge` must receive canonical packets, not raw chat
- `legacy-bridge` mode must preserve:
  - intent
  - risk tier
  - current phase
  - blockers
  - last known output
- summary compression must be deterministic enough that `Kernel -> legacy Claude-side`
  rollback does not lose operational meaning

## 9. Failure modes and controls

- `summary drift`
  - control: canonical packet schema and bounded sizes
- `split-brain between raw logs and summary`
  - control: raw logs are evidence only, summaries are execution input
- `fake progress`
  - control: progress is phase-based, not token-count based
- `artifact overload`
  - control: references over inline payloads
- `fallback inherits too much context`
  - control: fallback starts from compressed packets only

## 10. Implementation hooks

The first implementation slice should wire this into:

- `Kernel` orchestration packet assembly
- `happy-web` state adapter and task detail cards
- `kernel-mobile-progress`
- `kernel-recovery-console`
- `fugue-bridge` handoff packet generation

## 11. Acceptance criteria

- no mobile payload requires long raw logs
- no lane defaults to full-thread replay
- `amber` and above always produce compressed packets
- `hard-stop` always splits or restarts from compressed state
- `Kernel -> legacy Claude-side` rollback still preserves task meaning
