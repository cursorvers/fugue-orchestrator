---
name: x-auto-post-guard
description: Guardrail skill for drafting, scheduling, fixing, and manually posting x-auto posts. Use when working with x-auto Notion rows, quote posts, thumbnails, or any request that could change post status or publish to X. Enforces source-of-truth precedence, quote-post URL handling, schedule protection, and a mandatory preflight before posting, while leaving thumbnail art direction to a separate high-freedom skill.
---

# x-auto Post Guard

Use this skill whenever the task touches `x-auto` posting operations, including:

- drafting a new x-auto post
- editing `Body`, `Body JA`, `Source URLs`, `Image`, or `Status`
- scheduling or rescheduling a post
- manual posting from MBP
- quote-post workflows
- thumbnail replacement for an x-auto row

## Authority Order

Start from `docs/agents/x-auto-contract.md`.

Use this skill as the thin execution adapter for:

1. publication integrity and posting-mode checks
2. quote URL handling and Notion synchronization
3. runtime-specific audits when the task explicitly inspects live x-auto behavior

Specialized boundary:

- `docs/x-auto-note-linking-rule.md` applies only to lead posts for `note.com` articles.
- quote-post and reply-url flows stay governed by `docs/agents/x-auto-contract.md`.

## Non-Negotiable Rules

### 1. Never assume immediate posting

Default mode is `draft` unless the user explicitly asks to publish now.

If the user previously referenced a schedule slot such as `22:00`, treat that as an active scheduling constraint until they explicitly override it.

Before any manual MBP post, restate the posting mode in one line:

- `draft only`
- `approved for scheduler`
- `manual immediate publish`

If that mode is not explicit, do not publish.

### 2. Quote-post URL rule

For quote posts:

- body must not contain `x.com/` or `twitter.com/` URLs
- the reference URL must go to `source_url` / Notion `Source URLs`
- the scheduler or manual flow posts that URL as a reply
- if the body contains a quote URL, stop and fix it before posting

### 2.1 Note-lead URL rule

For `note.com` lead posts:

- keep the public `note.com` URL in the main body
- keep the same canonical URL in `source_url` / Notion `Source URLs`
- keep `reply_url` / Notion `Reply URLs` empty
- if a stale `Reply URLs` value remains on the row, clear it before calling the row scheduler-safe

### 3. Notion is the hub

Any change to text, image, status, or tweet linkage must be reflected in Notion in the same action window.

That includes:

- replacing thumbnails
- switching `draft` to `approved`
- switching `posted` back after manual deletion
- updating `Tweet ID`
- updating `Body` / `Body JA`

### 4. Manual MBP posting is emergency-only

Mac mini scheduler is the normal writer.

MBP direct posting is allowed only when the user explicitly wants a manual publish or emergency recovery. Do not silently use MBP posting as a convenience path.

When an emergency manual publish is approved:

- treat it as `manual immediate publish`
- preserve or explicitly discard the prior schedule in words before acting
- sync any operational metadata drift to Notion before hitting X
- verify queue removal/archive plus Notion `posted` state after publish

### 5. Length rule follows runtime safety, not the loosest prompt text

If the draft is meant to be a viable x-auto candidate for later approval or scheduling:

- treat `800-1500字` as the safe default target
- for `note.com` lead posts, aim for the shortest viable approved form rather than filling the full band
- note leads should read like a teaser that opens the article, not a self-contained summary that satisfies the whole curiosity loop
- prefer one sharp hook, one concrete operational tension, and one forward pull into the article over exhaustive bullet dumping
- do not rely on older `500-800字` drafting guidance when it conflicts with scheduler behavior
- if a shorter draft is requested for ideation only, label it explicitly as a non-posting draft
- short `note.com` lead posts are runtime-exempt from the general `800字` gate, but still require the usual explicit approval-state and schedule review before they are treated as scheduler-safe

Reason:

- runtime safety wins over prompt/profile looseness
- non-note sub-800 drafts may read fine but still fail later in scheduler validation
- note leads have a different editorial goal from standalone value posts: they should create momentum into the article, not consume the full appetite on X
- medical or AI-diagnostic framing is not exempt from source discipline just because it avoids explicit percentages or `研究` wording

### 6. Long-form line breaks are part of quality, not a final cosmetic pass

When drafting `800-1500字` posts, decide paragraph breaks while writing.

- treat each paragraph as one job: hook, diagnosis, evidence, pivot, implication, or conclusion
- keep most paragraphs to `1-3` sentences
- if a paragraph reaches `4` sentences or starts mixing multiple claims, split it
- after a hashtag line or quoted headline, leave a blank line before the first body paragraph
- prefer one short pivot paragraph before the main implication block
- let the final takeaway land in its own short paragraph when that improves emphasis
- avoid equal-sized slabs of text; readers should feel visual cadence
- avoid single-sentence spam where every line becomes its own paragraph
- if using `第一に / 第二に / 第三に`, either break the items visually or compress them into a clearly grouped block
- for English-default posts, use the same cadence: short hook, compact evidence blocks, one pivot, short landing

For `note.com` lead posts specifically:

- compress aggressively; do not spend the full length budget unless the post becomes unclear without it
- withhold at least one meaningful layer of explanation for the article itself
- avoid turning the lead into a mini-article with every key point already resolved
- end with a pull-forward line that makes the click feel necessary, not decorative

### 6.1 Japanese tone balance should stay in the middle register

For publish-facing Japanese body copy, follow `docs/agents/x-auto-contract.md` and keep the tone between over-assertive and overly polite.

- default to calm plain-form Japanese for the body
- do not stack hard assertions in consecutive sentences
- use softening only where uncertainty or scope limits justify it
- prefer `〜と見てよい`, `〜になりやすい`, `〜かもしれない`, `〜と考えられる`, `〜だろう`
- avoid absolutes such as `絶対`, `必ず`, `明らかに`, `完全に`, `〜しかない`, `断言できる`
- avoid over-polite filler such as repeated `〜と思います`, repeated `〜かもしれません`, `恐縮ですが`, `〜いただけますと幸いです`
- keep `です/ます` mostly for short reader-facing landing lines, not the entire body

## Mandatory Preflight

Before any publish action, verify all of the following and state any mismatch:

1. Posting mode: `draft`, `approved`, or `manual immediate`
2. Schedule: if a slot like `22:00` was mentioned, confirm whether it should still be preserved
3. Body language: English body vs Japanese body vs both
4. Quote handling: if this is a quote post, body has no X URL and `Source URLs` is present
   For note leads, also verify that the public `note.com` URL is in the body while `Reply URLs` is empty.
5. Thumbnail policy: whether the post should have an image, and whether the image already matches the final text
6. Notion target: existing row update vs creating a new row
7. Proper-noun leakage status for `Body` / `Body JA`: pass/fail, blocked terms found, and whether explicit user approval exists
   When the user requested abstraction/generalization, this check also covers source-derived branded phrases and site headlines.
   For medical or AI-diagnostic framing, also verify whether the copy implies patient-facing or clinical conclusions that require a non-X/non-note primary source before approval.
8. Runtime target: which live x-auto runtime is authoritative right now
   Check the active checkout's queue, heartbeat, logs, and process state before concluding that posting is broken. Do not rely only on legacy `Documents` paths or old launchd assumptions.
9. Metadata drift: whether the failure is truly missing assets vs stale QA flags
   If the local image exists and only `thumbnail_image_present`, `thumbnail_qa_verified`, `thumbnail_bytes`, or related fields are stale, repair queue + Notion metadata first.

If any item is ambiguous, stop before posting.

For new draft generation, also verify:

10. body length target: whether this draft is intended to be schedulable later (`800-1500字`) or just a short ideation stub
    For note leads, also ask whether the copy is the shortest viable approved teaser or an over-explained summary.
11. pillar/category/pattern mix: avoid overconcentrating on one pillar or one rhetorical pattern across a batch
12. line-break rhythm: whether the draft has a readable cadence rather than equal-sized walls of text
13. tone balance: whether the draft avoids both hard-assertion streaks and over-polite filler
    For Japanese body copy, verify that the default voice stays plain-form with selective softening instead of all-`です/ます`.

## English-for-auto-translation Rule

If the user wants English text that X auto-translation can render accurately into Japanese:

- use short declarative sentences
- prefer explicit subject-verb-object structure
- avoid idioms, sarcasm, slang, and compressed metaphors
- avoid ambiguous pronouns when possible
- keep terminology stable across the thread
- avoid em dashes and rhetorical fragments
- prefer `X is Y` / `X does Y` / `This means Y`

## Thumbnail Guard

If the request includes creating or replacing a thumbnail, or if the draft is being prepared as a complete x-auto candidate with image expectations, use `x-auto-thumbnail-art-director` alongside this skill.

Do not treat thumbnail-art-direction skill use as optional when:

- the user asks for more variety, better quality, or a new visual direction
- the current image feels repetitive or generic
- the request explicitly mentions Manus or asks for a premium render path
- the image is being replaced for an `approved` or schedule-bound row

Division of responsibility:

- `x-auto-post-guard`: publication integrity, Notion sync, posting mode, quote URL safety
- `x-auto-thumbnail-art-director`: image ideation, generation workflow, visual selection, and finish quality

When replacing a thumbnail for an x-auto row:

- inspect the rendered image, not only the source prompt
- check for text collisions, clipping, and language leakage inside the generated figure
- if overlay text changed, regenerate and sync Notion before any post or repost
- if a posted tweet is later deleted manually, the thumbnail fix still must be reflected in the Notion row that owns the asset
- prefer `scripts/local/integrations/xauto-thumbnail-gen.js` as the Manus-first generator entrypoint for x-auto assets

This guard does not prescribe thumbnail style.

- do not force a literal composition, visual motif, or prompt template unless the user asked for one
- do not block abstract, symbolic, logo-led, collage, cropped, overpainted, or post-processed approaches if they improve quality
- do not treat local editing, compositing, cropping, or art-directed cleanup as non-compliant
- use this skill to protect publication integrity, not to narrow visual exploration
- when the user is optimizing image quality, prefer multiple visual directions and select the strongest render before syncing Notion

Approved-file rule:

- only the explicitly approved final file may be synced to x-auto / Notion
- prefer `scripts/local/integrations/xauto-sync-approved-thumbnail.py` over ad-hoc copy + upload
- require hash parity between the approved file and the x-auto asset before pushing Notion
- if the body is already accepted by the user, lock `Body` / `Body JA` and iterate on image only
- if the user says the thumbnails feel repetitive, require at least 3 composition families before approval

## Delete / Repost Recovery

If a user says the posted tweet was manually deleted:

1. identify whether the deleted tweet was the current intended canonical post
2. restore or reset the Notion row accordingly
3. do not publish a replacement until posting mode and schedule are re-confirmed

If there were multiple posts in the same thread of work, never assume which one was deleted. Resolve that explicitly first.

## Minimal Operating Pattern

Use this sequence:

1. classify the task as `draft`, `schedule`, `repair`, or `publish`
2. run the mandatory preflight
3. update Notion draft/body/image first when needed
4. do not advance to `approved`, schedule, or publish while the leakage check is failing
5. publish only if `manual immediate publish` is explicit
6. after publish, verify `Tweet ID`, `Status`, `Posted At`, `Image`, and `Source URLs`

## Runtime Triage Addendum

Apply these heuristics before declaring an outage or hand-posting:

- If health scripts point at `Documents` or another legacy mirror, cross-check the active repo-local runtime before trusting the failure report.
- If Notion UI appears stale, verify the page directly by page ID before assuming sync failed.
- If a due post failed validation for thumbnail presence or QA, inspect the actual image file size. A real local asset with stale QA flags is a metadata repair task, not an image-generation task.
- If the user explicitly orders emergency recovery for a failed due post, repair metadata first, then post through the manual path, then verify queue archival and Notion `posted` status with `Tweet ID`.

## Session Failure That Triggered This Skill

This skill exists to prevent these exact mistakes:

- treating a scheduled `22:00` post as an immediate publish
- placing quote URLs in body text
- trusting a stale or conflicting instruction source over runtime behavior
- posting before confirming whether the previously deleted tweet was the canonical one
- changing a thumbnail after publication without first verifying visual layout
