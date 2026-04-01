---
name: thumbnail-gen
description: |
  Shared adapter for thumbnail and eyecatch generation across Claude and Codex.
  Use for note OGP images, X images, banners, and delegated image work from note-manuscript, note-generate, and x-auto.
---

# thumbnail-gen

Use this adapter when either runtime needs thumbnail policy.

Authority:
- `claude-config/assets/skills/thumbnail-gen/SKILL.md`
- `claude-config/assets/skills/thumbnail-gen/prompt-library.json`
- `claude-config/assets/skills/thumbnail-gen/scripts/`

Rules:
- Keep this adapter thin. Do not redefine prompt policy, engine priority, or QA thresholds here.
- Direct `/thumbnail` requests and delegated image work from `note-manuscript`, `note-generate`, and `x-auto` should all route here.
- If the source skill and a caller disagree, follow the source thumbnail skill.
- If the source files are missing, stop and report the missing path instead of improvising a new policy.
