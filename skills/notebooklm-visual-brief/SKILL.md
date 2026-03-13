---
name: notebooklm-visual-brief
description: "Create a source-grounded visual planning artifact through the local NotebookLM adapter in fugue-orchestrator. Use for mind maps, infographic briefs, diagram seeds, chronology seeds, or research visualization support that must return a bounded receipt instead of full artifact text."
---

# NotebookLM Visual Brief

Use this skill only in `/Users/masayuki/Dev/fugue-orchestrator`.

Load `../notebooklm-shared/SKILL.md` first if you need the shared safety rules.

## Supported Outputs

- `mind_map`
- `infographic`

## Command Shape

```bash
/Users/masayuki/Dev/fugue-orchestrator/scripts/lib/notebooklm-cli-adapter.sh \
  --action visual-brief \
  --title "<notebook title>" \
  --source-manifest "<path/to/sources.json>" \
  --artifact-type "<mind_map|infographic>" \
  --prompt "<focus text>" \
  --run-dir "<run dir>" \
  --resolve-only
```

For live execution, drop `--resolve-only` and pass approval flags only when the
task has been approved for external artifact creation.

## Execution Rules

- Build the source bundle first, then call the adapter once.
- Use `--artifact-type mind_map` for logic or relationship exploration.
- Use `--artifact-type infographic` only when the task explicitly needs a visual
  summary structure.
- For infographics, set `--orientation` and `--style` only when the user asks or
  the downstream design needs it.
- Return compact receipt fields or the receipt path, not the full NotebookLM
  artifact body.

## Refuse Or Block When

- no stable `--run-dir` is available
- the task asks for share/delete/public invite flows
- the source packet is already too large for bounded handling
- the result would require reinjecting NotebookLM transcript or report bodies
  into the main prompt
