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

## Thumbnail Doctrine Authority

- Still-image thumbnail doctrine authority is `thumbnail-gen/policy.md` plus `prompt-library.json`
  under the shared `claude-config` thumbnail skill.
- Content-marketing ad image patterns live only as abstract guidance in
  `prompt-library.json` key `contentMarketingAdGuidance`.
  Do not copy external prompt prose, paid-article text, or prompt catalogs into x-auto contracts, skills, queue rows, or runtime prompts.
- Adapters and runtimes such as `xauto-thumbnail-gen.js` may keep x-auto specific local text composition,
  delivery derivatives, and profile handling, but they must not redefine the shared still-image prompt doctrine or provider-order doctrine.
- Channel consumers such as `note-thumbnail-gen.js` may keep output-specific behavior, but they inherit
  the shared doctrine rather than forking it.

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

### Quote-post body-embed flow

Use this mode when the queue row refers to an X/Twitter status that should render as an embedded quote/card in the main post.

- `PARITY::X_QUOTE_URL_BODY_EMBED=true`.
- The X/Twitter status URL belongs in the main public body, normally as the final standalone URL.
- The same URL may remain in `Source URLs` as metadata and provenance.
- `Reply URLs` are reserved for non-X primary sources or supplemental citations and must not duplicate the X/Twitter status URL.
- The scheduler or manual posting flow must not move a body-embedded X/Twitter URL into the reply chain.
- Quote-style posts may still attach a compliant thumbnail image; body embedding the X/Twitter URL is not a reason to drop the image.
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
- For rows bound to Monday/Thursday `06:50`:
  - lead mode is required
  - the public `note.com` URL must remain in-body while `Reply URLs` stays empty
  - enforce a hard scheduler-safe teaser cap of `< 500字` for the body
  - if the row drifts into article-level distillation through exhaustive summary, chapter-like structure, or multiple fully resolved takeaways, treat it as non-compliant for that slot
  - non-compliant rows must not remain `approved`; rewrite or reschedule them before the slot
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
- If a user provides content-marketing ad prompt examples for seminar, exhibition, white paper, school, community, corporate training, advisory, or similar assets, extract only the abstract pattern: offer, audience, conversion goal, value promise, canvas/channel, layout zones, visible copy, hero visual, proof cue, tone, and negative constraints.
  Keep x-auto article thumbnails no-CTA by default; allow CTA-like image text only when the row is explicitly an ad, LP, email, signage, or campaign creative.
- If the user asks for abstraction or generalization, rewrite source-derived proper nouns, product labels, slogans, and branded UI text into neutral category language across `Body`, `Body JA`, live queue `text`, and visible thumbnail overlays.
- If a proper noun is needed only for evidence, keep it in `Source URLs` or internal notes, not in publish-facing body text or thumbnail overlays.
- When the source itself is a company site, note page, or branded announcement, keep the body conceptual and move entity-specific evidence to `Source URLs` rather than mirroring the branded headline into publish-facing copy.
- Before sync or posting, run a proper-noun leakage check across `Body`, `Body JA`, thumbnail prompt, and visible overlay text; if leakage exists without explicit user approval, rewrite or regenerate first.
- When the user explicitly asks to explain a named government publication, law, guideline, standard, court decision, or regulatory action, do not collapse the body into abstract commentary before reconstructing the concrete change.
  First identify from primary materials what the artifact actually is (`law`, `amendment`, `guideline`, `handbook`, `draft`, `public-comment proposal`, `press release`, etc.), its date/version, and whether it newly binds conduct or only interprets existing rules.
  Then surface at least `3` concrete source-grounded deltas or clarifications before moving to broader implications: what scope was added, what classification was introduced, what duties or examples were newly spelled out, what remains unchanged, and what is still left to courts or contracts.
  If the source is not actually a statute or amendment, say so plainly instead of writing as if `制定` or `改正` occurred.
- Auto-generated x-auto drafts may also enter this `一次情報詳細解説` mode without an explicit user override when the registry record already points to a primary source in an official, regulatory, standards, engineering-doc, or peer-reviewed domain.
  In that mode, do not optimize first for a broad thesis. Optimize first for artifact reconstruction: what the source is, what exactly it newly states, shows, releases, or constrains, and what still remains unproven or unchanged.
- If the generator cannot surface at least `3` concrete source-grounded points for such a source-explainer candidate, keep the row blocked or `draft` rather than emitting a polished abstract essay.
- For user-requested source explainers, necessary document titles, version labels, publication dates, and named制度 are allowed in `Body` / `Body JA`.
  This is a narrow exception to the default anti-leakage rule and applies only when those proper nouns are required to explain the primary-source delta accurately.
- Default publish-facing draft language is Japanese-only.
  Unless the user explicitly requests a non-posting translation artifact, write `title`, `Body`, and `Body JA` in Japanese and treat English or other Latin-script text as exception-only.
- If a phrase can be said naturally in Japanese, prefer Japanese.
  Reserve English or other Latin-script text for unavoidable short technical tokens or source-anchored terms that would become less accurate if translated away.
- English clauses, connective phrases, and stylistic flourishes are a review blocker in otherwise Japanese drafts.
  Keep English to the bare minimum required for clarity.
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

- Title is part of the publish-facing contract. Use a Japanese title of `15-30字` by default, and make it a compact claim, reader bottleneck, operational question, or concrete delta rather than a bare product name, source label, generic topic label, or placeholder.
- Use one idea per paragraph. Split when the role changes from hook, diagnosis, evidence, pivot, implication, or conclusion.
- Keep most paragraphs to `1-3` sentences. If a paragraph reaches `4` sentences or starts carrying multiple subclaims, split it.
- Inside one rhetorical block, put a line break after each Japanese full stop `。`.
  Do not insert a blank line after every sentence. Use a blank line only when the rhetorical block changes, such as hook to diagnosis, diagnosis to evidence, evidence to pivot, or pivot to conclusion.
- Do not leave publish-facing body text as dense multi-sentence paragraphs where one physical line contains several `。`.
  Do not solve this by making every sentence its own blank-line paragraph; sentence lines belong inside larger rhetorical blocks.
- Allow one short standalone pivot paragraph such as `ここが重要だ。`, `問題はここからです。`, or `だから次の論点が出てくる。` before the main implication block.
- End with a standalone landing paragraph when the conclusion is the key takeaway. Do not bury the final claim inside the longest paragraph.
- Prefer uneven rhythm over equal-sized slabs: medium paragraph, medium paragraph, short pivot, medium paragraph, short conclusion is better than five blocks with the same visual weight.
- Avoid turning every sentence into its own paragraph. The feed should feel breathable, not fragmented.
- Avoid long ordinal runs inside one wall of text. If using `第一に / 第二に / 第三に`, either break the items into separate visual units or tighten them into a clearly grouped block.
- After an opening hashtag line or quoted hook line, leave a blank line before the first body paragraph.
- When a body paragraph exceeds roughly `180-220` Japanese characters, review whether the reader is being asked to hold too many ideas before a visual pause.
- The 2026-04-17 hosted CI run `24547016917` for `cursorvers/x-auto` commit `6a37528` verified the Japanese-only prompt and paragraph-variance prompt. When skill prose, prompt snippets, or local memory drift on those points, restore from that GHA-backed behavior first. The `15-30字` title gate and sentence-line rule are contract rules layered on top of that GHA-backed floor; do not claim that run verified those two rules unless a newer CI adds explicit coverage.
- If the user explicitly requests English copy, treat it as a non-posting translation artifact unless they separately reconfirm x-auto publication mode. Use the same cadence: short hook, 1-2 compact evidence paragraphs, one pivot, then a short landing paragraph.

For `note.com` lead posts, also apply these teaser-specific constraints:

- stop before the article feels fully summarized
- do not enumerate every chapter or every takeaway from the linked note
- keep one unresolved implication, tension, or question alive into the click
- if a shorter formulation preserves intrigue better, prefer it over a more complete but flatter explanation

## Tone Balance for Japanese Body Copy

Publish-facing Japanese copy should sit between blunt assertion and fully polite service language.

- Use `です/ます` as the default body register for Japanese drafts.
  Keep plain-form and nominal endings for hooks, pivots, and final emphasis only.
- Avoid stacking strong assertions in consecutive sentences.
  One clear claim per paragraph is enough; let the surrounding sentences carry observation, condition, or implication.
- When certainty is limited, soften the conclusion rather than the evidence.
  Prefer forms such as `〜と見てよい`, `〜になりやすい`, `〜かもしれない`, `〜と考えられる`, or `〜だろう`.
- Avoid over-assertive absolutes such as `絶対`, `必ず`, `明らかに`, `完全に`, `〜しかない`, or `断言できる` unless the source truly warrants them.
- Avoid over-polite filler such as repeated `〜と思います`, repeated `〜かもしれません`, `恐縮ですが`, or `〜いただけますと幸いです`.
- Do not make the whole draft blandly polite.
  Keep the claim clear, but land it in courteous Japanese.

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
