---
name: x-auto-thumbnail-art-director
description: High-freedom art direction skill for x-auto thumbnails. Use when a post image feels generic, repetitive, over-constrained, or needs a stronger visual identity. Optimized for Manus-first generation plus local compositing, cropping, and finish work.
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

Shared policy lives in `docs/agents/x-auto-contract.md`.
This skill should stay focused on the image-specific delta.

## Goal

Produce the best final image for the x-auto row, not the purest prompt.

This skill is not advisory-only. When an x-auto request includes thumbnail creation, replacement, quality uplift, or complaints about repetition, use a Manus-first generation path for x-auto rather than defaulting to ad-hoc local redraws.

The image may come from:

- a single strong Manus generation
- multiple Manus generations with selection
- Manus generation plus local crop / composite / cleanup
- a hybrid where local post-processing improves a near-miss render

## Freedom Defaults

Default to high freedom.

- abstract and symbolic directions are allowed
- logo-led or emblem-led composition is allowed if it raises recognizability
- typography is optional, not required
- human figures are optional, not required
- asymmetry, cropping, blur, overpaint, glow, texture, and compositing are all allowed
- use post-processing when the generator gets 80 percent of the way there

Do not overfit to a fixed house format unless the user explicitly asks for consistency.

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
3. Generate with Manus first using `scripts/local/integrations/xauto-thumbnail-gen.js` or an equivalent Manus-backed x-auto flow.
4. Inspect the actual image, not the prompt.
5. If a render is close but flawed, fix it locally instead of throwing it away immediately.
6. Compare candidates at feed size and reject the one that feels closest to the previous few x-auto rows.
7. Sync only the strongest final image to the x-auto row.

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
- prefer Manus-backed generation over local-only redraws
- treat local compositing as finish work, not the primary creativity path
