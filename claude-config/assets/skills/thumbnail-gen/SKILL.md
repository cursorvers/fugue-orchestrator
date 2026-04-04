---
name: thumbnail-gen
description: |
  Canonical thumbnail policy entrypoint for claude-config.
  Keep this file thin for skill loaders; detailed design policy lives in policy.md.
---

# thumbnail-gen

Use this source skill for `/thumbnail`, サムネイル, バナー, アイキャッチ, and OGP image work.

Authority:
- `claude-config/assets/skills/thumbnail-gen/policy.md`
- `claude-config/assets/skills/thumbnail-gen/prompt-library.json`
- `claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-gen.js`
- `claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-manus.js`
- `claude-config/assets/skills/thumbnail-gen/scripts/thumbnail-gate2.js`

Contract:
- Keep this entrypoint thin. Do not inline the full KAWAI framework, layout catalog, or style examples here.
- Load `policy.md` only when detailed concept, copy, layout, or quality guidance is needed.
- Treat `prompt-library.json` as the runtime style/template source of truth.
- Treat `scripts/` as the execution source of truth for engine routing, quality gates, and output behavior.
- Preserve shared skill compatibility for `note-manuscript`, `note-generate`, and `x-auto`; do not rename the skill or break the prompt-library schema casually.

Minimum workflow:
1. Freeze the asset goal, channel, and required text before generating.
2. Use an explicit style when the caller provides one; otherwise let the runtime auto-detect from the prompt/title.
3. Default to `auto` engine routing. Manus should be reserved for explicit `manus` requests or person-heavy prompts detected by `shouldUseManus()`.
4. Preserve the output contract: `1280x670` PNG, Gate 1 size floor, and Gate 2 readability checks when enabled.
5. Escalate to `policy.md` only when the task needs the detailed KAWAI framework, title-pattern logic, layout rules, or style examples.

On-demand references:
- `claude-config/assets/frameworks/TITLE_FRAMEWORK.md`
- `claude-config/assets/frameworks/HOOK_FRAMEWORK.md`
- `claude-config/assets/frameworks/CONTENT_RECIPES.md`
- `claude-config/assets/frameworks/FEEDBACK_PROTOCOL.md`
