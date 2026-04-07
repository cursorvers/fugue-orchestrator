# X-auto Contract
# SSOT: Repo-visible x-auto drafting and sync invariants for Codex/Claude adapters.

## Purpose

This document is the repo-visible source of truth for x-auto skill scope,
posting-mode invariants, and lead-post vs quote-post boundaries.

Adapter skills such as `x-auto-post-guard` and `x-auto-thumbnail-art-director`
must stay thin and point here for shared policy.

## Authority Order

1. This file for repo-visible scope, invariants, and adapter boundaries.
2. `docs/x-auto-note-linking-rule.md` for the specialized lead-post note-link case.
3. The active x-auto runtime implementation and tests when a task explicitly audits or changes live posting behavior.

## Scope Matrix

### Lead-post note link

Use this mode when the queue row is the main post that introduces a `note.com` article.

- The public `note.com` URL belongs in the main post body.
- The same rule applies to `Body` and `Body JA` for bilingual rows.
- `Source URLs` stores the canonical article URL as the source reference.
- `Reply URLs` must be empty in this mode; if a stale reply URL remains on the row, clear it before treating the row as scheduler-safe.
- The body should behave like a lead, not a substitute for the article.
- Prefer short, curiosity-preserving teaser copy over exhaustive on-platform summarization.
- Under the current runtime, schedulable note leads still need to satisfy the active approval gates.
  That means operators should write the shortest viable approved teaser, not a maximally complete thread-length summary.

### Quote-post or reply-url flow

Use this mode when the queue row refers to an external post that should be reply-posted rather than embedded in the main body.

- The main body must not contain `x.com/` or `twitter.com/` URLs.
- The reference URL belongs in `Source URLs`.
- The scheduler or manual posting flow may publish that URL as a reply.
- Do not apply the lead-post note-link rule to this mode.

## Shared Invariants

- Default posting mode is `draft` unless the user explicitly requests scheduling or immediate publish.
- Notion DB is the sole editable source of truth for `Body`, `Body JA`, `Source URLs`, `Image`, `Status`, and `Scheduled`.
- If the user edits copy or schedule in Notion DB, the next sync must reflect that Notion value rather than preserving a stale local cache or Supabase-derived mirror.
- Local queue JSON, Supabase, and runtime caches may supplement non-Notion fields such as downloaded image paths or published tweet metadata, but they must not overwrite a newer Notion field value for content or schedule.
- Quoted-author registry data may live in Supabase or other supplemental stores for diversity tracking and provenance, but it must remain advisory metadata rather than a second editable source of truth for publish-facing copy or schedule.
- Automated candidate generation may create only new `draft` rows. It must never set `approved`, `posting`, `posted`, `Scheduled`, `Tweet ID`, `Posted At`, or `Force Post`.
- Candidate drafts must carry explicit provenance metadata and at least one non-X primary-source URL before they are eligible for human review.
- Outcome-like numeric claims in publish-facing copy must be directly traceable to a primary source.
  Do not approve or publish drafts that assert effect sizes such as `9割`, `2倍`, or `15%減`, or that claim medical outcome improvements, unless the cited source directly supports that scope and is reachable from `Source URLs` or `Reply URLs`.
- Medical or AI-diagnostic framing also requires a primary source even when no numeric effect size is stated.
  If the copy claims implications for `AI診断`, `医療AI`, patient understanding, clinical explanation, or similar patient-facing medical context, require a non-X/non-note primary-source URL before approval or publish.
- Journal-name-only authority references are insufficient.
  Phrases such as `JAMA 2025` or `Nature MedicineのRCT` without a directly traceable source URL must be treated as unsupported for approval/publish decisions.
- Citation existence is not enough; citation context fit is required.
  Before scheduling, approving, reposting, or manual publishing, verify that the linked source actually matches the body's central claim and does not create a misleading example-to-claim jump.
- For claim-heavy external milestone events, do not default to generic commentary.
  If the source concerns a first-of-its-kind approval, regulatory mitigation, legal change, clinical launch, safety incident, or other milestone in a high-stakes domain such as medicine, law, or finance, first reconstruct from primary sources:
  1. what happened,
  2. what did not happen,
  3. which jurisdiction and date govern the event,
  4. which mechanism authorized it, and
  5. whether and how the same thing would differ in Japan when the post frames implications for Japan.
- In those milestone cases, the draft should normally contain an explicit judgment or thesis about the event itself.
  Do not abstract the body into a broad AI/innovation essay unless the user explicitly asks for abstraction or the primary facts are too weak to support event-level commentary.
- Fixed scheduler slots are `06:50`, `11:50`, `16:50`, and `21:00` JST.
- Monday and Thursday `06:50` are reserved for self-authored `note.com` lead posts; non-note rows must not consume that slot.
- When a post fails validation, distinguish missing assets from metadata drift.
  If the local image file exists and only thumbnail QA flags or byte counts are stale, repair queue + Notion metadata before treating the post as unpostable.
- Thumbnail generation and replacement must not silently change posting mode.
- For schedulable draft candidates, prefer the runtime-safe target of `800-1500字` unless the user explicitly asks for a non-posting short draft.
- For rows created on or after `2026-03-30`, `<800字` is a hard publish blocker for non-exempt rows.
  Non-exempt short rows must not remain `approved`; they require rewrite or demotion before the scheduler reaches the slot.
- For `note.com` lead posts, editorial intent is different even when the runtime gate is the same:
  stay as short as possible under the active note-lead exemption, preserve an open loop, and avoid resolving the full article in-body.
  Do not apply that note-lead brevity logic to ordinary external-source commentary unless the user explicitly requests a short ideation stub.
- `queue_audit: PASS` means only that the current mechanical audit passed.
  It must not be interpreted as publish permission when approval-state drift, citation mismatch, or manual post-approval edits exist.
- Any manual Notion edit to `Body`, `Body JA`, `Source URLs`, `Reply URLs`, `Image`, or `Scheduled` after approval invalidates that approval.
  Reapproval is required before scheduling or publishing again.
- Default to non-commercial language and visuals; do not include person names, company names, product names, handles, or brand slogans in `Body`, `Body JA`, or image text unless the user explicitly requests them.
- If the user asks for abstraction or generalization, rewrite source-derived proper nouns, product labels, slogans, and branded UI text into neutral category language across `Body`, `Body JA`, live queue `text`, and visible thumbnail overlays.
- If a proper noun is needed only for evidence, keep it in `Source URLs` or internal notes, not in publish-facing body text or thumbnail overlays.
- When the source itself is a company site, note page, or branded announcement, keep the body conceptual and move entity-specific evidence to `Source URLs` rather than mirroring the branded headline into publish-facing copy.
- Before sync or posting, run a proper-noun leakage check across `Body`, `Body JA`, thumbnail prompt, and visible overlay text; if leakage exists without explicit user approval, rewrite or regenerate first.
- Before concluding that x-auto is not running, verify the active runtime directly from the current checkout's queue, heartbeat, logs, and live process state rather than relying only on legacy launchd paths or `Documents` mirrors.
- If Notion UI and local queue disagree, prefer direct page/database reads over UI impressions or stale cache snapshots. Treat page-ID verification as canonical.
- When changing scheduler guardrails or posting validation logic, treat file edits and live activation as separate steps.
  Recurrence prevention is not complete until the active scheduler process is confirmed to be running the new code path.
- If a posted tweet was manually deleted and must be reposted, restore the owning row only after confirming the deleted tweet was the intended canonical post, then re-sync body, image, and source metadata before re-publish.
- For repost recovery, remove stale or context-mismatched `Source URLs` / reply citations before re-publish instead of carrying them forward by default.
- Thumbnail text layout is part of message quality, not a cosmetic afterthought. When overlay text is used, vary the text architecture across a batch instead of reusing the same polite upper-left card by default.
- If the current overlay is readable but visually timid, allow the text block to become a primary compositional mass through edge panels, stacked bands, central strips, or other bolder placements that still preserve feed-size legibility.

## Long-Form Line-Break Rhythm

For `800-1500字` x-auto candidates, optimize paragraph breaks for scanability on X, not for essay purity.

- Use one idea per paragraph. Split when the role changes from hook, diagnosis, evidence, pivot, implication, or conclusion.
- Keep most paragraphs to `1-3` sentences. If a paragraph reaches `4` sentences or starts carrying multiple subclaims, split it.
- Allow one short standalone pivot paragraph such as `ここが重要だ。`, `問題はここからです。`, or `だから次の論点が出てくる。` before the main implication block.
- End with a standalone landing paragraph when the conclusion is the key takeaway. Do not bury the final claim inside the longest paragraph.
- Prefer uneven rhythm over equal-sized slabs: medium paragraph, medium paragraph, short pivot, medium paragraph, short conclusion is better than five blocks with the same visual weight.
- Avoid turning every sentence into its own paragraph. The feed should feel breathable, not fragmented.
- Avoid long ordinal runs inside one wall of text. If using `第一に / 第二に / 第三に`, either break the items into separate visual units or tighten them into a clearly grouped block.
- After an opening hashtag line or quoted hook line, leave a blank line before the first body paragraph.
- When a body paragraph exceeds roughly `180-220` Japanese characters, review whether the reader is being asked to hold too many ideas before a visual pause.
- In English-default posts, use the same cadence: short hook, 1-2 compact evidence paragraphs, one pivot, then a short landing paragraph. Do not dump five medium English paragraphs without a rhythm change.

For `note.com` lead posts, also apply these teaser-specific constraints:

- stop before the article feels fully summarized
- do not enumerate every chapter or every takeaway from the linked note
- keep one unresolved implication, tension, or question alive into the click
- if a shorter formulation preserves intrigue better, prefer it over a more complete but flatter explanation

## Tone Balance for Japanese Body Copy

Publish-facing Japanese copy should sit between blunt assertion and fully polite service language.

- Default to calm plain-form Japanese (`常体`) for the body.
  Do not convert the whole post into `です/ます` unless the user explicitly wants a more service-like tone.
- Avoid stacking strong assertions in consecutive sentences.
  One clear claim per paragraph is enough; let the surrounding sentences carry observation, condition, or implication.
- When certainty is limited, soften the conclusion rather than the evidence.
  Prefer forms such as `〜と見てよい`, `〜になりやすい`, `〜かもしれない`, `〜と考えられる`, or `〜だろう`.
- Avoid over-assertive absolutes such as `絶対`, `必ず`, `明らかに`, `完全に`, `〜しかない`, or `断言できる` unless the source truly warrants them.
- Avoid over-polite filler such as repeated `〜と思います`, repeated `〜かもしれません`, `恐縮ですが`, or `〜いただけますと幸いです`.
- Use polite endings sparingly for reader-facing landing lines only.
  As a default rhythm, no more than one polite-ending sentence per `3-4` sentences.

## Adapter Roles

- `skills/x-auto-post-guard/SKILL.md`
  - publication integrity
  - posting mode
  - quote URL safety
  - Notion synchronization
  - runtime health and metadata-drift triage for failed/manual posts
- `skills/x-auto-thumbnail-art-director/SKILL.md`
  - thumbnail ideation
  - generation workflow
  - visual quality review
  - approved asset selection
