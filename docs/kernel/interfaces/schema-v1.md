# Kernel Interface Schema v1

## Goal

Freeze the minimum shared schemas before parallel implementation so `Track A: secret plane`, `Track B: runtime enforcement`, `Track C: auto-compact`, and `Track D: doctor/handoff` can evolve without drifting.

This document is `Kernel-only`. It does not rename or rewire the legacy Claude-side runtime.

## 1. Canonical Secret Schema

### Contract

The canonical shared secret names are:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `ZAI_API_KEY`
- `GEMINI_API_KEY`
- `XAI_API_KEY`
- `ESTAT_API_ID`
- `TARGET_REPO_PAT`
- `FUGUE_OPS_PAT`

### Resolution order

Runtime resolves shared secrets in this order:

1. `process env`
2. `Keychain`
3. `shared SOPS bundle`
4. `explicit external env file`

The encrypted shared bundle is the canonical bootstrap / restore source and a disaster-recovery fallback. Routine attended operation should be satisfied by process env or Keychain, but runtime loaders may use the bundle before falling back to an explicitly configured external env file.

### Compatibility

- `XAI_API` is a legacy alias for `XAI_API_KEY`.
- `ESTAT_APP_ID` is a legacy alias for `ESTAT_API_ID`.
- New runtime code should emit and consume canonical names only.
- Doctor views must print source and length only, never secret values.

## 2. Bootstrap Receipt Schema

Bootstrap receipt is the startup contract for one `Kernel run`.

### Required fields

- `run_id`
- `recorded_at`
- `project`
- `purpose`
- `tmux_session`
- `codex_thread_title`
- `owner`
- `phase`
- `mode`
- `lane_count`
- `providers`
- `active_models`
- `active_model_count`
- `manifest_lane_count`
- `has_agent_labels`
- `has_subagent_labels`
- `required_models`
- `required_evidence`

### Notes

- `run_id` is the machine identifier.
- `project + purpose` is the human-facing identifier.
- `tmux_session` identifies the handoff target.

## 3. Runtime Ledger Schema

Runtime ledger is the mutable state for one `Kernel run`.

### Required fields

- `state`
- `reason`
- `receipt_path`
- `updated_at`
- `phase`
- `mode`
- `active_models`
- `blocking_reason`
- `next_action`
- `provider_usage`
- `last_event`
- `last_event_at`

### State values

- `healthy`
- `degraded`
- `blocked`

## 4. Compact Artifact Schema

Compact artifact is the bounded handoff summary for one `Kernel run`.

### Required fields

- `run_id`
- `project`
- `purpose`
- `current_phase`
- `mode`
- `tmux_session`
- `owner`
- `active_models`
- `blocking_reason`
- `next_action`
- `decisions`
- `summary`
- `last_event`
- `updated_at`

### Hard limits

- `summary`: max 3 lines
- `decisions`: max 3 items
- `next_action`: max 1 item
- `blocking_reason`: max 1 item

## 5. Doctor View Schema

`doctor` is read-only. It displays, but does not define, truth.

### Display priority

1. `run_id`
2. `project`
3. `purpose`
4. `tmux_session`
5. `phase`
6. `mode/state`
7. `next_action`
8. `compact present`
9. `receipt present`
10. `runtime health`

## 6. Handoff Contract

- `1 request = 1 Kernel run`
- `1 tmux session = 1 Kernel run`
- `1 Kernel run = 1 Codex thread`
- `project + purpose` identifies the run for humans
- physical tmux session naming uses a shell-safe slug, not the human label directly
- `run_id` identifies the run for machines
