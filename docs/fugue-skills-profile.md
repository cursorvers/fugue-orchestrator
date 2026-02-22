# FUGUE Skills Profile (Codex/Claude Shared)

This profile defines a curated subset of OpenClaw skills that are useful for
FUGUE operations and safe enough for default adoption.

## Goals

- Keep skill behavior consistent when main orchestrator switches (`codex` <-> `claude`).
- Prevent prompt-injection style drift from uncurated third-party skills.
- Avoid auto-execution guidance that can bypass FUGUE governance gates.

## Baseline Source of Truth

Manifest:

- `config/skills/fugue-openclaw-baseline.tsv`

Sync script:

- `scripts/skills/sync-openclaw-skills.sh`

## Selected Skills

Required profile:

- `github`: GH issue/PR/workflow/log operations used by the control plane.
- `model-usage`: per-model usage visibility for throttling and budget decisions.
- `tmux`: stable control of long-running interactive sessions.

Optional profile (`--with-optional`):

- `obsidian`: local markdown knowledge capture and runbook linking.
- `summarize`: fast context extraction from URL/video/file inputs.

## Security Policy

The sync script enforces:

1. Pinned source ref (`OPENCLAW_REF`, default pinned SHA in script).
2. Frontmatter validity checks (`name`, `description`, `---`).
3. Blocklist on clearly unsafe auto-execution flags in `SKILL.md`:
   - `--yolo`
   - `--full-auto`
4. Non-managed directory protection:
   - Existing skill directories are not replaced unless `--force` is set.

## Install Examples

Both orchestrators, required profile only:

```bash
./scripts/skills/sync-openclaw-skills.sh --target both
```

Include optional skills:

```bash
./scripts/skills/sync-openclaw-skills.sh --target both --with-optional
```

Dry-run preview:

```bash
./scripts/skills/sync-openclaw-skills.sh --target both --with-optional --dry-run
```

## Operational Rule

When adding new third-party skills to FUGUE, update the baseline manifest and
keep this profile provider-agnostic. Do not add skills that contain
auto-approval/unsafe execution guidance unless explicitly sandboxed and reviewed.
