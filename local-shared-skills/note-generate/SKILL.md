---
name: note-generate
description: |
  Shared adapter for the note article end-to-end pipeline across Claude and Codex.
  Use for article generation, QC, review submission, note draft upload, X lead generation, and x-auto handoff.
---

# note-generate

Use this adapter for the full note publication pipeline.

Authority:
- `claude-config/assets/skills/note-generate/SKILL.md`
- `claude-config/assets/skills/note-generate/scripts/`

Rules:
- Treat the source skill above as the workflow authority.
- Keep runtime behavior aligned across Claude and Codex by using this adapter as the shared entry point.
- Thumbnail work inside this pipeline must delegate to `thumbnail-gen`; do not embed separate image policy here.
- If the source skill is missing or unreadable, stop and report the path instead of reconstructing the workflow from memory.
