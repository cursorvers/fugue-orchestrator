---
name: notebooklm-shared
description: "Shared rules for NotebookLM thin skills in fugue-orchestrator. Use when a task in this repo needs NotebookLM through the local nlm CLI adapter with bounded receipts, run-local storage, resolve-only checks, or approval-gated execution."
---

# NotebookLM Shared Rules

Use this skill only in `/Users/masayuki/Dev/fugue-orchestrator`.

## Adapter

Call:

```bash
/Users/masayuki/Dev/fugue-orchestrator/scripts/lib/notebooklm-cli-adapter.sh
```

Do not call the upstream generic `nlm-skill` flow from this repo profile.

## Required Rules

- Always set `--run-dir` so receipts and raw outputs stay under a run-local
  `notebooklm/` directory.
- Prefer `--resolve-only` before live execution when checking a route or
  debugging command shape.
- Keep outputs bounded. Return the receipt path or compact receipt fields, not
  transcript bodies or full artifact text.
- Treat NotebookLM outputs as `artifact-only` evidence. They are not
  control-plane truth.
- Do not use NotebookLM share/delete flows from the baseline FUGUE profile.

## Approval Rules

- Read-only resolution checks may use `--resolve-only`.
- External create actions must honor adapter approval gates.
- If the task requires human approval, pass both:
  - `--ok-to-execute true`
  - `--human-approved true`

## Receipt Contract

Expect:

- `schema_version`
- `action_intent`
- `notebook_id`
- `artifact_id`
- `artifact_type`
- `raw_output_path`
- `is_truncated`
- `sensitivity`
- `ttl_expires_at`

If those are missing, treat the run as invalid.
