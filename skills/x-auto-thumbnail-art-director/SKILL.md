---
name: x-auto-thumbnail-art-director
description: High-freedom art direction adapter for x-auto thumbnails. Use when a post image feels generic, repetitive, over-constrained, or needs a stronger visual identity. Keep shared thumbnail-gen doctrine authoritative, then add x-auto-specific variation, delivery, and finish work.
---

# x-auto Thumbnail Art Director

Use this skill when the user wants a stronger thumbnail, especially if they ask for:

- more distinctive or premium visuals
- a less repetitive format
- more abstract or symbolic imagery
- stronger brand presence such as Claude, OpenAI, Cursor, or product cues when the user explicitly asks for them
- fewer guardrails and more creative freedom

Use it together with `x-auto-post-guard` when:

- the image belongs to a real x-auto row or draft candidate
- the text is being prepared for eventual scheduling or approval
- Notion sync and publication safety must stay aligned with the image work

Authority:

- shared generation doctrine:
  `$HOME/Dev/claude-config/assets/skills/thumbnail-gen/policy.md`
- shared content-marketing ad patterns:
  `$HOME/Dev/claude-config/assets/skills/thumbnail-gen/prompt-library.json` key `contentMarketingAdGuidance`
- x-auto operational integrity:
  `docs/agents/x-auto-contract.md`

This skill is a specialized x-auto adapter layered on top of the shared thumbnail-gen doctrine.
It should stay focused on the image-specific delta, not become a second prompt-design authority.

When using pasted content-marketing ad prompt examples, extract only the abstract pattern and never replay external prompt prose. Keep x-auto's no-CTA article-thumbnail default unless the row is explicitly an ad, LP, email, signage, or campaign creative.

## Goal

Produce the best final image for the x-auto row, not the purest prompt.

For still-image prompt design, `thumbnail-gen/policy.md` is authoritative and newer than this adapter.
Use the same ChatGPT Images 2.0-first editorial precision rules as note thumbnails, then widen exploration only where x-auto genuinely benefits from extra variation.
Apply the project `DESIGN.md` gate in the x-auto thumbnail generator by default; use `XAUTO_THUMBNAIL_DESIGN_MD` or `CURSORVERS_DESIGN_MD` only when a task-local design contract should override the Cursorvers project default.
In interactive/manual Codex sessions, that first line may be Codex built-in `gpt-image-2`. In scripted/backend x-auto flows, keep the existing API-driven runtime chain.

This skill is not advisory-only. When an x-auto request includes thumbnail creation, replacement, quality uplift, or complaints about repetition, use a ChatGPT Images 2.0-first generation path for x-auto rather than defaulting to ad-hoc local redraws.

The image may come from:

- a single strong ChatGPT Images 2.0 or Manus generation
- multiple ChatGPT Images 2.0 / Manus generations with selection
- ChatGPT Images 2.0 or Manus generation plus local crop / composite / cleanup
- a hybrid where local post-processing improves a near-miss render

## Freedom Defaults

Default to high freedom after satisfying the shared editorial baseline.

- abstract and symbolic directions are allowed
- logo-led or emblem-led composition is allowed if it raises recognizability
- typography is optional, not required
- human figures are optional, not required
- asymmetry, cropping, blur, overpaint, glow, texture, and compositing are all allowed
- use post-processing when the generator gets 80 percent of the way there

Do not overfit to a fixed house format unless the user explicitly asks for consistency.
Do not override the shared GPT Image 2 prompt structure for composition zones, overlay architecture, typography intent, and edit-first behavior.

## Kawaii Systems Principle

For x-auto conceptual thumbnails, default to a `kawaii systems` design philosophy unless the post clearly calls for another visual language.

`kawaii` here does not mean mascots or childish decoration. It means:

- approachable intelligence
- tactile warmth
- asymmetrical friendliness
- emotionally readable silhouettes
- a small amount of surprise or delight
- visual softness without losing seriousness

Use it to create variety, not sameness.

Good signals:

- rounded or tactile modules mixed with sharper system geometry
- layered depth that feels inviting instead of sterile
- contrast that stays legible at feed size
- shapes that are memorable without becoming toy-like
- text architecture that can carry visual weight when overlay text is present

Bad signals:

- the same left-card/right-object scaffold repeated with new colors
- a timid headline card that stays readable but never becomes part of the composition
- flat corporate dashboard art
- anonymous hero faces used as filler
- abstract geometry with no emotional temperature

## Preferred Workflow

1. Identify what feels weak in the current thumbnail.
2. Choose at least 3 visual directions with genuinely different composition logic.
3. For interactive/manual Codex work, you may ideate or edit with Codex built-in `gpt-image-2` first. For scripted/backend x-auto flow, generate with ChatGPT Images 2.0 via API first, then Manus, then NB2 using `scripts/local/integrations/xauto-thumbnail-gen.js` or an equivalent supported x-auto flow.
4. Start from the shared thumbnail-gen editorial prompt structure, then add x-auto-specific differentiation such as stronger asymmetry, feed novelty, or brand cue emphasis.
5. Inspect the actual image, not the prompt.
6. If a render is close but flawed, prefer local edits or targeted regeneration over a full prompt reset.
7. Compare candidates at feed size and reject the one that feels closest to the previous few x-auto rows.
8. Sync only the strongest final image to the x-auto row.

When overlay text is present:

- treat text placement as one of the main variation axes, not as a fixed afterthought
- vary between edge panel, center band, badge stack, ribbon rail, or other clear text architectures
- if the background is strong but the text feels timid, re-compose locally before regenerating the background
- prefer one version where the headline block is a primary mass, not just a label

## Visual Directions To Consider

- Hero emblem: one dominant brand mark with sculptural depth
- Abstract system: layers, traces, slabs, and geometry with no literal scene
- Editorial object: one iconic object or tile photographed like a magazine cover
- Cropped artifact: extreme crop of a strong render for more tension and boldness
- Hybrid collage: generated base plus local isolation, blur, gradient, or compositing
- Orbital kawaii: rounded modules, traces, bubbles, and system motion
- Sticker field: tactile blocks, soft panels, floating accents, and warm contrast
- Ribbon stage: vertical accents, tall negative space, and layered planes
- Edge stack: dark edge panel, assertive headline mass, and a nearby accent spine

## Quality Bar

Reject thumbnails that feel like:

- generic AI office art
- a repeated template with only prompt words swapped
- low-contrast shapes that disappear at feed size
- brandless abstract visuals when brand recognition is strategically useful
- any composition that is materially the same as the last accepted thumbnail for that series
- text that is technically readable but visually secondary when the post needs a forceful thesis

Prefer thumbnails with:

- one clear focal point
- a memorable silhouette
- strong value contrast at small size
- intentional negative space
- material richness and finish
- visible differentiation from the previous few x-auto thumbnails in the same batch
- enough emotional character that the post is recognizable without reading every word
- overlay text that either anchors the frame or actively challenges the main object, instead of politely floating beside it

## Brand Guidance

If the user explicitly asks for a brand cue such as Claude:

- make the brand cue unmistakable
- do not bury it inside a busy scene
- it can be a logo tile, emblem, sculptural mark, or symbolic brand object
- if exact logo reproduction is unreliable, use a strong brand-adjacent emblem plus the right color and material language

If the user did not explicitly ask for a brand cue:

- default to neutral, generalized, or kawaii-systems abstraction
- do not inject product names, UI labels, logos, or brand tiles on your own

## Sync Rule

This skill owns visual quality. `x-auto-post-guard` owns publication integrity.

This skill does not decide:

- posting mode
- whether a draft should stay `draft` or move to `approved`
- whether quote URLs belong in body text
- whether a text is long enough to be a scheduler-safe x-auto candidate

Those decisions stay with `x-auto-post-guard` and the x-auto runtime rules.

After choosing the final image:

- sync through `scripts/local/integrations/xauto-sync-approved-thumbnail.py`
- never point Notion at an in-progress render or a file whose hash parity with the x-auto asset has not been verified
- leave posting mode unchanged unless the user explicitly asks to publish

## Minimum Operational Standard

When the user says thumbnails feel repetitive, generic, low quality, or wants more variation:

- do not stop at a single render
- produce at least 3 candidates from different composition families
- prefer Codex built-in `gpt-image-2` first in interactive/manual Codex runs, or ChatGPT Images 2.0 API first in scripted/backend x-auto runs, then Manus, before falling back to Gemini or local-only redraws
- treat local compositing as finish work, not the primary creativity path
