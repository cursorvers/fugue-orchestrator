# Source: AGENTS.md §11 — Local Linked Systems
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 11. Local Linked Systems (Video/Note/Obsidian)

- Local direct mode can chain external systems in parallel after Tutti integration.
- Source of truth:
  - `config/integrations/local-systems.json`
- Linked runner:
  - `scripts/local/run-linked-systems.sh`
- Adapter scripts:
  - `scripts/local/integrations/*.sh`
- Safety gate:
  - `run-local-orchestration.sh --linked-mode execute` must only run when `ok_to_execute=true`; otherwise skip.
- **v8.6**: Issue comment posting is now default (`POST_ISSUE_COMMENT=true`).
  - `run-local-orchestration.sh --with-linked-systems` auto-passes `--comment` to the linked runner.
  - Results from Remotion, note-manuscript, Obsidian, Discord, LINE are auto-posted to the originating issue.
  - Consumer repo dispatch-back: set `CONSUMER_REPO` and `TARGET_REPO_PAT` env vars to send results via `repository_dispatch`.
