---
name: note-manuscript
description: |
  Shared adapter for long-form note manuscript drafting across Claude and Codex.
  Use for thesis shaping, fact-led drafting, staged refinement, and thumbnail handoff after the manuscript stabilizes.
---

# note-manuscript

Use this adapter when the task is manuscript-first rather than full publication automation.

References:
- `scripts/local/integrations/note-semi-auto.sh`
- `claude-config/assets/skills/note-generate/SKILL.md`

Rules:
- Start with audience, thesis, and required evidence.
- Verify time-sensitive or contested claims against primary sources before polishing prose.
- Distinguish confirmed facts from inference.
- Once the manuscript title and framing are stable, delegate eyecatch work to `thumbnail-gen`.
