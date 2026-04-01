# Source: AGENTS.md §9 — Shared Skills Baseline
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 9. Shared Skills Baseline (Codex/Claude)

- FUGUE useful third-party skills must be curated and pinned.
- Baseline manifest:
  - `config/skills/fugue-openclaw-baseline.tsv`
- Shared sync script (provider-agnostic):
  - `scripts/skills/sync-openclaw-skills.sh`
- Profile details:
  - `docs/fugue-skills-profile.md`
- Vendor-specific skill profile:
  - `docs/googleworkspace-skills-profile.md`
- Vendor-specific manifest:
  - `config/skills/googleworkspace-cli-baseline.tsv`
- Vendor-specific sync script:
  - `scripts/skills/sync-googleworkspace-skills.sh`
- Repo-local shared manifest:
  - `config/skills/local-shared-baseline.tsv`
- Repo-local shared sync script:
  - `scripts/skills/sync-local-shared-skills.sh`
- Repo-local shared adapter root:
  - `local-shared-skills/`

Security guardrails:
- Do not install unpinned third-party skills directly from `main`.
- Reject skills with unsafe auto-execution guidance (`--yolo`, `--full-auto`) in default profile.
- Keep Codex and Claude skill sets synchronized from the same manifest so orchestrator switching does not change capabilities.
- Keep repo-owned shared skills (`thumbnail-gen`, `note-manuscript`, `note-generate`, `x-auto`) synchronized to both runtimes from the local shared manifest.
- Keep repo-owned shared adapters thin. Runtime-neutral entry points live in `local-shared-skills/`; source skills and repo docs remain authoritative references.
- If `~/.claude/skills` aliases `claude-config/assets/skills`, do not overwrite it with the sync script. Manage Claude-side adapters in the source tree and sync adapters to Codex separately.
- Prefer `SKILL.md + CLI` over MCP by default for Google Workspace because it keeps the active context surface smaller and preserves provider-agnostic parity.
- Reserve `gws mcp` for MCP-only clients or when structured tool exposure is explicitly required.
