# ChatGPT GPT -> Kernel Semi-Automatic Import

## Why This Exists

There is no official one-click import from ChatGPT custom GPTs into `Codex`, `Kernel`, or `Happy.app`.

The durable path is:

1. capture the GPT configuration
2. normalize it into a small JSON file
3. store it under a linked source directory
4. generate implementation-ready fragments
5. review and merge only the durable parts

This keeps `Kernel` sovereignty intact and preserves Claude-side reversibility.

## Semi-Automatic Boundary

Automated:

- source normalization
- linked source storage
- registry update for repeatable re-generation
- `AGENTS.md` fragment generation
- `CODEX.md` fragment generation
- `Happy.app` inbox preset generation
- skill seed generation

Human review required:

- reject GPT-specific hidden-tool assumptions
- move only durable governance into `AGENTS.md`
- move only Codex-facing operator behavior into `CODEX.md`
- decide whether the GPT should become a reusable skill
- resolve conflicts with `Kernel` / Claude-side doctrine

## Command

Generate a starter template:

```bash
bash /Users/masayuki/Dev/fugue-orchestrator/scripts/local/transform-chatgpt-gpt-to-kernel.sh \
  --template /Users/masayuki/Dev/tmp/gpt-import-template.json
```

Generate Kernel-facing artifacts:

```bash
bash /Users/masayuki/Dev/fugue-orchestrator/scripts/local/transform-chatgpt-gpt-to-kernel.sh \
  --input /Users/masayuki/Dev/tmp/my-gpt.json \
  --output-dir /Users/masayuki/Dev/tmp/my-gpt-kernel-import
```

Generate a linked source-of-truth entry and repeatable outputs:

```bash
bash /Users/masayuki/Dev/fugue-orchestrator/scripts/local/transform-chatgpt-gpt-to-kernel.sh \
  --input /Users/masayuki/Dev/tmp/my-gpt.json \
  --linked-root /Users/masayuki/Dev/fugue-orchestrator/config/gpt-imports
```

## Generated Files

- `kernel-import-report.md`
- `AGENTS.fragment.md`
- `CODEX.fragment.md`
- `happy-inbox-preset.json`
- `skill-seed.md`

## Linked Mode

`--linked-root` creates a one-way repeatable link:

- source GPT config is copied to `config/gpt-imports/<slug>/source.gpt.json`
- generated artifacts are written under the same slug directory unless `--output-dir` is given
- `config/gpt-imports/registry.json` is updated

This is not a live sync with ChatGPT.
It is a durable semi-automatic bridge:

```text
ChatGPT GPT builder
  -> manual capture once
  -> source.gpt.json
  -> transformer
  -> Kernel / Happy.app fragments
```

## Recommended Review Order

1. `kernel-import-report.md`
2. `AGENTS.fragment.md`
3. `CODEX.fragment.md`
4. `skill-seed.md`
5. `happy-inbox-preset.json`

## Critical Review Questions

- does the GPT rely on hidden ChatGPT-only tools?
- does it assume Claude-first or GPT-first sovereignty?
- should this be an inbox preset instead of a skill?
- does any instruction violate `risk-gated autonomy`?
- can actions be expressed with `skill-cli` or `REST bridge` instead of MCP?

## Relation To Happy.app

`happy-inbox-preset.json` is the mobile-facing bridge.

The intended flow is:

```text
ChatGPT GPT config
  -> semi-auto transformer + linked registry
  -> Happy.app inbox preset
  -> Kernel intake packet
  -> Codex sovereign routing
  -> optional Claude-side rollback
```
