---
name: notebooklm-slide-prep
description: "Create a source-grounded slide draft artifact through the local NotebookLM adapter in fugue-orchestrator. Use for slide-deck preparation that should hand off a bounded receipt to downstream slide tooling instead of injecting full draft content into context."
---

# NotebookLM Slide Prep

Use this skill only in `/Users/masayuki/Dev/fugue-orchestrator`.

Load `../notebooklm-shared/SKILL.md` first if you need the shared safety rules.

## Supported Output

- `slide_deck`

## Command Shape

```bash
/Users/masayuki/Dev/fugue-orchestrator/scripts/lib/notebooklm-cli-adapter.sh \
  --action slide-prep \
  --title "<notebook title>" \
  --source-manifest "<path/to/sources.json>" \
  --prompt "<presentation goal>" \
  --run-dir "<run dir>" \
  --resolve-only
```

For live execution, drop `--resolve-only` and pass approval flags only when the
task has been approved for external artifact creation.

## Execution Rules

- Use this skill to produce a source-grounded slide artifact for downstream
  slide generation, not as the final slide renderer.
- Keep the NotebookLM output at receipt level and hand off by stable reference.
- Use one adapter call per slide-prep task to keep the receipt surface small.

## Refuse Or Block When

- no stable `--run-dir` is available
- the task needs a final rendered deck directly inside main context
- the task asks for NotebookLM share/delete/public invite flows
