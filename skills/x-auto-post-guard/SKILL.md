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

Start from `docs/agents/x-auto-contract.md` when the current project provides it.

If the project does not ship that file, fall back in this order:

1. project `CLAUDE.md` / `AGENTS.md`
2. this skill

Use this skill as the thin execution adapter for:

1. publication integrity and posting-mode checks
2. quote URL handling and Notion synchronization
3. runtime-specific audits when the task explicitly inspects live x-auto behavior

Specialized boundary:

- `docs/x-auto-note-linking-rule.md` applies only to lead posts for `note.com` articles.
- quote-post and reply-url flows stay governed by `docs/agents/x-auto-contract.md`.

Editorial boundary:

- `@cursorvers` centers on clinical / healthcare AI governance, implementation, operations, and AI build practice.
- pharmaceutical R&D, drug discovery, and biotech pipeline commentary are off-core by default
- do not draft drug-discovery or pharma-deal posts unless the user explicitly requests that angle or the source directly changes clinical governance / hospital operations / bedside decision-making
- if a source is mainly about pharma partnerships, target discovery chemistry, or preclinical licensing structure, block it from default queue promotion and suggest a more on-brand healthcare-AI angle instead
- do not open posts with meta source-framing such as `今回の一次情報は`
- avoid throat-clearing lead-ins that explain the source before the claim; start with the claim, delta, risk, or reader impact instead
- primary audience is clinicians and healthcare operators who are curious about AI, not engineers
- avoid engineer-only wording unless it is unavoidable and immediately translated into everyday Japanese
- terms such as `MCP`, `API`, `sandbox`, `harness`, `append-only log`, `novelty search`, `ABM`, `SDK`, `monitoring`, and `governance` should be replaced or glossed in plain language for public-facing drafts
- if a technical term must remain, explain it in the same sentence; do not leave unexplained developer jargon in a publish-facing draft
- if a technical term must remain, add the plain-language gloss in the same sentence (`API（外部サービスとの接続口）` style); drafts with unexplained engineer terms stay blocked
- for AI-tool posts, do not write feature laundry or benchmark worship; anchor the draft on the reader's bottleneck, what actually moves forward, and what still requires human judgment or operational design
- for AI-tool posts, separate product capability from organizational responsibility; do not imply that a tool itself guarantees domestic data residency, regulatory compliance, audit logging, or approval workflow unless the primary source explicitly says so
- for AI-tool posts, block unsupported release-note inflation: do not add model names, release dates, benchmark scores, compatibility claims, or healthcare-compliance wording unless verified in a primary source
- if an AI-tool draft reads like a release-note summary with no clear operational thesis for clinicians or healthcare operators, keep it in `draft` and rewrite before promotion
- for AI-tool posts, do not casually center patient data, clinical records, or other sensitive medical data as the default usage example; prefer general business or personal productivity data unless the post is explicitly about compliant handling, governance, or approved secure architecture

## Non-Negotiable Rules

### Runtime safety essence

- `dry-run` means no remote mutation: no Notion upsert, no queue write, no X action.
- Test flows must not write to the real Notion database unless explicitly opted in.
- Runtime config and tests are authoritative over prose limits or stale skill text.
- When current prompt/profile prose conflicts with hosted GitHub Actions-verified behavior, treat that as policy drift. Inspect `.github/workflows/ci.yml`, `auto_generator.py`, and the relevant tests before following stale prompt text.
- The 2026-04-17 hosted GitHub Actions evidence covers the Japanese-only prompt, paragraph-variance prompt, and dense-paragraph normalization floor; broader title and sentence-line policy comes from this skill contract unless newer CI explicitly verifies it.
- GHA vote-bridge validation requires dry-run packages to remain `draft`; `approved` requires an explicit approval path, never an inferred one.
- After live queue or Notion mutation, verify before/after audit and leave audit errors at zero.
- Treat Notion rows as source of truth; local JSON, image paths, and caches are derived unless the repo contract says otherwise.
- Treat Notion active rows as source-of-truth queue rows even when they are missing from local `post_queue.json`; a due `approved + Scheduled` Notion-only row must not be ignored by scheduler inspection or manual incident triage.
- Do not resurrect local-only Notion-backed rows that are absent from the active Notion query; absence normally means terminalization or queue removal unless a valid dirty local override is intentionally being pushed.
- For fixed-slot exceptions such as `22:00 JST`, verify `Schedule Mode=operator_override` and `Schedule Override Reason` before attributing a miss to timezone or clock drift.
- Short posts still require prose QA: heading-like breaks, uniform paragraph cadence, and abstract-only claims are approval risks.
- Live Notion DB creation is limited to real queue rows with `Status=draft` or `Status=approved`; terminal statuses are PATCH-only operational outcomes on existing rows.
- Do not create live Notion rows for synthetic placeholders such as `xxxxxxxx...`, even when a helper says it is only a smoke test.
- Smoke, regression, and dry-run flows must not mutate the live Notion DB. If an explicitly live-mutating manual check is unavoidable, terminalize its own artifact with a populated `Failure Reason` in the same work window.

### 0. Progress reporting is mandatory in work reports

Whenever you give a progress-style work report during an x-auto task, include both of these on one line near the top:

- `達成度: xx%`
- `残り: 約yスライス`

Rules:

- base the percentage on the concrete task objective currently being worked
- estimate `スライス` as the number of meaningful remaining work chunks, not elapsed time
- update the numbers whenever the task scope changes materially
- if the objective is already complete, report `達成度: 100% / 残り: 約0スライス`

### 1. Never assume immediate posting

Default mode is `draft` unless the user explicitly asks to publish now.

If the user previously referenced a schedule slot such as `22:00`, treat that as an active scheduling constraint until they explicitly override it.

Draft rows are not schedule reservations. Do not leave `Scheduled` / `scheduled_for` on a `draft` row. When demoting, canceling approval, or keeping a post as a draft, clear the schedule in the same operation. Set schedule only in the same action that moves the row to `approved`, unless the user explicitly asks for an analysis-only draft artifact outside the live queue.

Treat `draft + Scheduled` as a residue incident, not a held slot. Do not use it for slot occupancy; clear `Scheduled` first, then re-enter the normal approval flow if the user wants that row scheduled.

Treat Notion `Image` as authoritative and local `image_path` as a delivery cache. If a user clears the Notion `Image`, do not resurrect it from stale local cache; if a post has a Notion `Image` URL but no local file, materialize the URL into the local images cache before publish-time media upload.

Before any manual MBP post, restate the posting mode in one line:

- `draft only`
- `approved for scheduler`
- `manual immediate publish`

If that mode is not explicit, do not publish.

### 2. Quote-post URL rule

For quote posts:

- `PARITY::X_QUOTE_URL_BODY_EMBED=true`
- body must contain the X/Twitter status URL, normally as the final standalone URL
- the same reference URL may remain in `source_url` / Notion `Source URLs` as metadata
- `Reply URLs` are for non-X primary sources or supplemental citations and must not duplicate the X/Twitter status URL
- never use X API `quote_tweet_id`; x-auto quote delivery is main post body embed, optionally with a compliant thumbnail image
- if `source_url`, `quote_url`, or `Reply URLs` contains an X/Twitter status URL, `publish_core.py` must keep `quote_tweet_id=None`, append the URL to `post_text` when absent, and avoid adding it to `reply_lines`
- when the user asks to create a quote-based post from an account that is not already watched, ask one short follow-up: whether that account should also be added to the future quote watchlist
- treat watchlist addition as a separate config choice from the current draft request; do not silently add unrelated accounts
- if the user explicitly says `引用投稿者リストに入れておいて` or equivalent, update `trend_scanner.py` `WATCH_ACCOUNTS` in the same task and do not ask again

### 2.1 Note-lead URL rule

For `note.com` lead posts:

- do not create a note lead while the article is still only a manuscript or note draft
- require an issued public article URL in canonical form: `https://note.com/<account>/n/<id>`
- do not treat profile URLs, top-page URLs, draft/editor URLs, preview URLs, magazine URLs, or placeholder URLs as sufficient
- when the user provides a share preview URL such as `https://note.com/preview/<id>?prev_access_key=...`, use it only to verify the draft/preview content and extract `<id>`; never place the preview URL or `prev_access_key` in `Body`, `Body JA`, `Source URLs`, `Reply URLs`, logs intended for publication, or final user-facing copy
- if the account is known, derive the expected future public URL as `https://note.com/<account>/n/<id>` from the preview ID, but mark it as `pending_public_verification` until the canonical public URL resolves without the preview key
- a preview URL can support editorial review and X-lead copy drafting, but it does not satisfy the scheduler-safe publication gate for `Status=approved`
- keep the public `note.com` URL in the main body
- keep the same canonical URL in `source_url` / Notion `Source URLs`
- keep `reply_url` / Notion `Reply URLs` empty
- treat `note.com` URLs in both body and `Reply URLs` as a hard duplicate-link blocker; clear `Reply URLs` before approval or posting instead of relying on the scheduler to suppress the reply
- if a stale `Reply URLs` value remains on the row, clear it before calling the row scheduler-safe
- if the public `note.com` URL is missing from the main body, the row is invalid even when `source_url` is correct
- if the public canonical URL has not been issued yet, stop at manuscript/draft stage and do not create or sync the X lead row
- exception: if the user explicitly authorizes pre-approval for a note article that is scheduled to auto-publish shortly before a reserved X slot, the row may be set to `approved` only when the expected canonical URL is already known, `Reply URLs` is empty, all note-lead text gates pass, and a pre-slot public URL check is scheduled to report or intervene before posting
- do not treat `Source URLs` as a substitute for in-body note linking; the reader-facing click target belongs in the body itself

### 2.2 External-article synthesis rule

For article-driven posts that start from an external URL and are not quote posts:

- keep the main body URL-free unless the post is a `note.com` lead
- put the canonical article URL in `source_url`
- put `1-3` strengthening primary sources in `reply_url` when the body makes a stronger claim than the source article alone
- if the source is adjacent to healthcare rather than clinical itself, explicitly name the transfer layer: `governance`, `infodemic management`, `monitoring`, `intervention design`, or `ops`
- do not upgrade a public-sector, defense, finance, or social-media system into a clinical AI claim without medical-device-grade evidence
- when discussing medical AI applicability, separate `direct clinical use` from `supporting governance / monitoring / communication infrastructure`

### 2.3 Primary-source delta reconstruction rule

For posts that explain a named government publication, law, guideline, standard, court decision, or regulatory action:

- do not default to abstract summary first
- reconstruct from primary sources what the artifact actually is: `law`, `amendment`, `guideline`, `handbook`, `draft`, `public-comment proposal`, `press release`, or similar
- state the date / version when available
- verify whether the event is an actual `制定` / `改正` or only a `公表` / `とりまとめ` / `解釈整理`
- if the user says `今回何が変わったのか`, the body must surface at least `3` concrete source-grounded deltas or clarifications before broader implications
- preferred delta types are: new scope, new classification, new examples, new duties, clarified limits, unchanged points, and issues left to courts, contracts, or future guidance
- if the currently cited source is secondary or a social post, fetch the linked primary document before drafting whenever possible
- auto-generated candidates may also enter this mode when the registry already points to a primary source in an official, regulatory, standards, engineering-doc, or peer-reviewed domain
- in that auto-selected mode, do not optimize first for broad commentary; start from artifact reconstruction and concrete source-grounded points
- if you cannot surface at least `3` concrete points, keep the row blocked or `draft` instead of producing a polished abstract essay
- when the user explicitly wants a source explainer, necessary proper nouns such as official document titles, law names, version labels, and dates may remain in the body; do not over-abstract them away
- only after the concrete deltas are laid out may you compress them into a higher-level implication paragraph

### 2.4 `06:50` note-lead hard gate

For rows scheduled for Monday or Thursday `06:50 JST`:

- only `note.com` lead mode is allowed
- the public `note.com` URL must appear in the main body
- keep the same canonical URL in `source_url` / Notion `Source URLs`
- keep `reply_url` / Notion `Reply URLs` empty
- the body must remain teaser-form, not article-level distillation
- keep `Body` and `Body JA` each under `500字` as the scheduler-safe cap for that slot
- if the body resolves the article on-platform through exhaustive summary, chapter-like unpacking, or multiple fully solved takeaways, reject it for `06:50`
- if a `06:50` row drifts out of note-lead compliance, do not leave it `approved`; rewrite or move the row to a non-note slot first

### 2.5 Note-lead repair protocol

When a reserved-slot `note.com` lead is found in a non-compliant state:

- repair the main body first so the public `note.com` URL is visibly embedded in the body text
- clear any stale `reply_url` / Notion `Reply URLs`
- preserve the existing thumbnail unless the user explicitly asks to replace it
- keep the row in `approved` only after the note-lead checks pass again
- if the row still reads like a full article recap after repair, demote or reschedule it instead of leaving a silent policy violation behind

### 2.6 Category / Pattern completeness and sequence balance

For any row that will remain `approved`:

- `category` and `pattern` must both be explicitly set; blank values are invalid
- when reordering a batch, shuffle the approved sequence to reduce back-to-back reuse of the same `category` or `pattern`
- keep reserved `note.com` lead slots fixed in place while rebalancing the rest of the queue
- do not treat quote posts, note leads, or primary-source posts as exempt from metadata completeness
- if perfect alternation is impossible, prefer minimizing adjacent duplication rather than preserving the old order

### 3. Notion is the hub

Any change to text, image, status, or tweet linkage must be reflected in Notion in the same action window.

That includes:

- replacing thumbnails
- switching `draft` to `approved`
- switching `posted` back after manual deletion
- updating `Tweet ID`
- updating `Body` / `Body JA`

### 3.1 Manual failed transition gate

Before turning any row into `failed` manually:

- inspect authority first with `python3 scripts/inspect_post_authority.py --post-id <id>`
- do not leave `Failure Reason` blank
- record at least `class / detected_at / operator / evidence / next_action / summary`
- do not treat `failed` as a temporary parking status
- do not move `failed -> approved` directly; repair and return to `draft` first
- if the row is `failed` or `missed` without a reason, treat that as an incident and repair the metadata in the same work window
- if you are requeueing a failed row, clear the stale terminal state only after the root cause is written down and the row content or metadata has actually been repaired
- if the same title or headline was already published once, block requeueing or cloning it as a new row; repost is prohibited even if the original tweet was later deleted manually
- after a posting lock is acquired, any publish exception must release the lock by setting a terminal operational state, normally `failed`, with `Failure Reason`; never leave a row in `posting` as the final state of an intervention

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

- title is part of the post contract, not an internal memo
- use a Japanese title of `15-30字` by default
- write the title as a compact claim, reader bottleneck, operational question, or concrete delta
- do not use a bare product name, source label, generic topic label, or placeholder title
- if the title cannot tell the reviewer what the post argues, rewrite before presenting or syncing
- treat each paragraph as one job: hook, diagnosis, evidence, pivot, implication, or conclusion
- keep most paragraphs to `1-3` sentences
- if a paragraph reaches `4` sentences or starts mixing multiple claims, split it
- after a hashtag line or quoted headline, leave a blank line before the first body paragraph
- prefer one short pivot paragraph before the main implication block
- let the final takeaway land in its own short paragraph when that improves emphasis
- avoid equal-sized slabs of text; readers should feel visual cadence
- reject paragraph runs where `3` or more adjacent body blocks over `70字` land within roughly the same length band (`max-min <= 20字`); this looks machine-templated even when the writing is accurate
- deliberately vary paragraph weight by rhetorical job: short hook, medium diagnosis, longer evidence, short pivot, medium implication, compact landing
- when several evidence paragraphs naturally have similar length, combine one, split one, or turn one into a short contrast/pivot so the visual rhythm follows the argument instead of a template
- do not solve this by making every sentence a separate paragraph; variance should come from context, not chopped-up line spam
- avoid single-sentence spam where every line becomes its own paragraph
- avoid making `第一に / 第二に / 第三に` the default structure. It is allowed occasionally for true checklists, but repeated use across drafts makes the feed look automated and evasive
- before using ordinal framing, ask whether the same points can read more naturally as scene-based contrast, cause-and-effect, a short checklist without ordinal labels, or a narrative pivot
- if using ordinal framing, either break the items visually or compress them into a clearly grouped block, and avoid reusing that structure in the next same-batch draft unless the user explicitly asks for it
- when unavoidable Latin-script terms appear, keep the same cadence: short hook, compact evidence blocks, one pivot, short landing

Sentence-line rule:

- inside one rhetorical block, put a line break after each Japanese full stop `。`
- do not insert a blank line after every sentence
- use a blank line only when the rhetorical block changes, such as hook to diagnosis, diagnosis to evidence, evidence to pivot, or pivot to conclusion
- do not leave publish-facing body text as dense multi-sentence paragraphs where one physical line contains several `。`
- do not solve this by making every sentence its own blank-line paragraph; sentence lines belong inside larger rhetorical blocks
- bullets are allowed for true checklists, but ordinary prose should follow the sentence-line plus block-blank-line rule

Runtime/GHA restoration rule:

- match `_normalize_long_form_line_breaks()` in `auto_generator.py`: split dense body blocks before they exceed roughly `140字`, after `3` sentences, or when the next sentence starts with a real pivot such as `ここが重要`, `一方で`, `ただ`, `つまり`, `だから`, or `結局`
- the GHA-covered tests in `tests/test_auto_generator.py` expect generated long-form drafts to be normalized into multiple paragraphs and keep the maximum paragraph length at or below `140字`
- use the runtime rule as a floor, not as a template. `140字` and `3文` prevent walls of text; they do not permit equal-sized chopped paragraphs
- the 2026-04-17 hosted CI run `24547016917` for `cursorvers/x-auto` commit `6a37528` verified the Japanese-only prompt and paragraph-variance prompt; when skill prose drifts on those points, restore from that GHA-backed behavior first
- the `15-30字` title gate and sentence-line rule are skill contract rules layered on top of that GHA-backed floor; do not claim that run verified those two rules unless a newer CI adds explicit coverage
- when repairing an already-accepted body for line breaks only, preserve wording and verify that removing whitespace from old and new text yields the same content
- if `prompt_rules.json`, `account_profile.py`, or generator prompt text still says English-by-default or suggests weaker line-break handling, treat it as stale drift for publish-facing x-auto drafts and follow this GHA-backed rule

### 6.0.1 Repetitive formula guard

Drafts should not converge on a visible template.

- do not reuse the same rhetorical skeleton across consecutive posts, especially `第一に / 第二に / 第三に`, `重要なのは3つ`, `見るべき点は3つ`, or equivalent numbered-list framing
- treat formula repetition as an automation smell even when each individual post is factually correct
- vary the structure by source and argument: use concrete scene opening, risk-to-remedy, before/after contrast, one-question FAQ, operational implication, or short narrative landing when appropriate
- if a draft begins to sound like the previous x-auto draft with only the topic swapped, rewrite the structure before syncing or presenting it

### 6.1 AI-tool post structure is fixed unless the user explicitly wants a different shape

For public-facing posts about Claude Code, Cursor, MCP-like tooling, coding agents, or other AI build tools:

- start from the reader's real bottleneck, not from the vendor announcement
- explain in plain Japanese what part of work actually moves forward
- state clearly what still depends on human review, local policy, or team operations
- prefer the sequence `現場の詰まりどころ → 使える理由 → 残る責任 → 実務上の示唆`
- keep flashy capability lists subordinate to the operational point
- if the draft cannot answer `それで医療者の仕事は何が楽になり、何は楽にならないのか`, rewrite it

#### 6.1.1 P2 black-screen onboarding pattern

Use this pattern for non-engineer AI-build posts when the source is a lived-experience quote about trying Claude Code, Cursor, terminal work, GitHub, VS Code, or a similar tool and getting stuck at the first screen.

Successful reference: 2026-04-16 JST `@cursorvers` post quoting `@researcher_cvs`, headline `『AIが黒い画面で止まってしまう』`.

Structure:

- quoted-headline hook that names the visible blockage, not the tool feature
- concrete scene: SNS hype, small paid trial, first screen, confusion, closing the app
- normalization: frame the failure as a common first-step problem, not lack of talent
- root-cause reframe: the wall is not model performance; it is inability to verbalize what to ask AI to do
- minimal path: pick one AI, pay a small amount if needed, use it as a thinking partner
- prompt examples: show 2-3 actual questions the reader can paste or adapt
- context bridge: for academia or work, name the next practical environment such as GitHub Education, VS Code, paper collection, summarization, citation work, or simple LP creation
- tool demystification: translate GitHub / VS Code / terminal into a plain everyday role such as `作業履歴を残すノート`
- operating loop: small ask, inspect result, revise, keep the record
- landing: compact action formula with concrete counts, e.g. `1つのAI、1つの困りごと、30分の実験`

Quality checks:

- keep the reader as the subject; do not make the post a claim about being advanced at AI
- avoid benchmark, release-note, and feature-list framing
- include at least one directly reusable prompt sentence when the post teaches first-step AI use
- if the post embeds a live X quote URL for card rendering, that is the current x-auto quote-body rule (`PARITY::X_QUOTE_URL_BODY_EMBED=true`)
- if turning this into an x-auto row later, keep the X/Twitter status URL in `Body` / `Body JA` as the final standalone URL and keep `Reply URLs` for non-X citations only

For `note.com` lead posts specifically:

- compress aggressively; do not spend the full length budget unless the post becomes unclear without it
- withhold at least one meaningful layer of explanation for the article itself
- avoid turning the lead into a mini-article with every key point already resolved
- end with a pull-forward line that makes the click feel necessary, not decorative

### 6.2 Japanese tone balance should stay firm but courteous

For publish-facing Japanese body copy, follow `docs/agents/x-auto-contract.md` and keep the voice closer to courteous expert commentary than hard manifesto prose.

- use `です/ます` as the default body register for Japanese drafts
- keep plain-form and nominal endings for hooks, pivots, and final emphasis only
- do not stack hard assertions in consecutive sentences, especially `〜だ。`, `〜ではない。`, `〜ことだ。`, `〜からだ。`, or `〜しかない。`
- if a paragraph has two hard plain-form endings in a row, rewrite one into `〜です`, `〜といえます`, `〜が必要です`, `〜と整理できます`, or `〜にあります`
- preserve confidence through evidence and concrete checks, not through harsher endings
- use scope-limited certainty such as `この条件では〜です`, `少なくとも〜が必要です`, `現時点では〜と整理できます`
- avoid weak hedge fillers such as repeated `〜と思います`, `〜かもしれません`, `ではないでしょうか`, `恐縮ですが`, `〜いただけますと幸いです`
- avoid absolutes such as `絶対`, `必ず`, `明らかに`, `完全に`, `〜しかない`, `断言できる` unless they are directly grounded in a cited rule or source
- do not make the whole draft blandly polite; keep the claim clear, but land it in courteous Japanese

#### 6.2.1 Critical Japanese editorial QA

Run this QA before presenting, syncing, or approving Japanese `Body` / `Body JA`.

- fail the draft if `です/ます` has been replaced by weak customer-support language; `恐縮ですが`, `幸いです`, and repeated hedges are not the target voice
- fail the draft if hard endings do the work of evidence. A strong claim needs a source, concrete check, owner, threshold, date, or operational consequence
- check sentence endings inside each paragraph. If two or more hard plain-form endings appear back-to-back, rewrite one to courteous certainty instead of softening the claim
- check paragraph lengths after splitting on blank lines. Ignore blocks under `70字`, hashtags, and quoted source lists; for the remaining body blocks, reject any adjacent run of `3+` where `max-min <= 20字`
- when a Japanese draft lists three or more parallel checks, criteria, risks, or unresolved items, format them as Markdown bullets (`- ...`) instead of separate sentence-like lines ending in `。`; checklist rhythm should read as a list, not as chopped paragraphs
- do not fake variance by chopping every sentence into its own paragraph. Prefer one of: combine two similar evidence blocks, split one mixed-purpose block, or create a short pivot paragraph that marks a real turn in the argument
- check formula repetition across the batch. If consecutive drafts use the same skeleton (`第一に/第二に/第三に`, `3つあります`, or equal-length evidence slabs), rewrite at least one structure
- when repairing already-approved Notion rows whose substance is good, prefer whitespace-only paragraph reflow. Verify `remove_all_whitespace(old) == remove_all_whitespace(new)` and preserve schedule/status/source/image properties
- if tone, paragraph rhythm, and source grounding cannot all be satisfied, keep or return the row to `draft`; do not leave a polished but policy-weak row as scheduler-safe

### 6.3 Publish-facing body copy is Japanese-only

For x-auto publish-facing drafts, Japanese is mandatory. Do not create English-body or bilingual posts.

- keep `Title`, `Body`, and `Body JA` Japanese. `Body JA` should not be treated as a secondary translation field for an English `Body`
- this Japanese-only rule overrides stale English-by-default wording in `account_profile.py`, `prompt_rules.json`, generator prompts, archived skill copies, or memory fragments unless a newer GHA-verified runtime contract explicitly replaces it
- if the repo contains both Japanese-only and English-by-default instructions, treat the latter as drift, produce Japanese publish-facing copy, and mention the drift only when it affects the task outcome
- if the user asks for English copy, treat it as a non-x-auto translation artifact; do not sync it into the live queue as publish-ready copy
- if a phrase can be written naturally in Japanese, do so
- allow English or other Latin-script text only for unavoidable short technical tokens such as `AI` or `API`, or for source-anchored terms that would become less accurate if translated away
- allow proper nouns, product names, organization names, journal names, standards, API paths, and URLs when needed, but keep the surrounding sentence Japanese
- block full English sentences, English CTAs, English-first hashtags, and bilingual paragraph pairs
- for medical AI source explainers, translate source terms into plain Japanese after the first mention; examples: `ambient AI scribe` -> `診療中の会話から記録を支援するAI`, `clinical infrastructure` -> `臨床現場を支える基盤`, `quintuple aim` -> `医療の5つの目標`, `clerical burden` -> `事務作業の負担`, `workflow` -> `業務の流れ`
- for paper-driven medical AI governance explainers, do not leave source clauses in English. Translate terms such as `procurement`, `local configuration`, `consequential value judgments`, `quietly codified`, `adaptive and deployed at scale`, `tradeoffs`, `post-deployment recalibration and learning`, `clinicians' immediate awareness`, `durable, scalable defaults`, and `contest` into plain Japanese like `調達`, `院内設定`, `患者ケアに影響する価値判断`, `静かに組み込まれる`, `広い範囲で使われ導入後も調整されうる`, `何を優先し何を諦めるか`, `導入後の再調整と学習`, `臨床家がその場で気づきにくい範囲`, `長く残り広く効く既定値`, and `異議を出す`
- do not keep English article subtitles, metric names, or paper phrasing as-is when a natural Japanese rendering is enough; translate first, and keep the English only when it is a proper noun or necessary search anchor
- do not leave English clauses, connective phrases, or stylistic fillers inside an otherwise Japanese draft
- if Latin-script text exceeds the minimal exception budget, rewrite or regenerate before the row can stay review-eligible. Use judgment rather than pure character-ratio blocking so proper nouns do not cause false positives

### 6.4 Same-topic replay discipline is stricter than text similarity

Do not treat semantic near-duplicates as acceptable just because the wording changed.

- if a recent post and a candidate share the same core claim, same lesson, or same landing, treat that as a collision even when string similarity is low
- changing only the headline, metaphors, or paragraph order is not enough
- when the topic is intentionally revisited, require a different angle: new evidence, different stakeholder, different failure mode, different time horizon, or opposite strategic implication
- if the tone arc is also the same, reject the draft even when the examples differ
- homage is allowed only after a multi-month gap, and only when the new draft clearly signals a new lens instead of a rewrite
- for same-week or same-day reuse, bias to `do not post`

### 6.5 Concreteness gate blocks abstract essays

For schedulable drafts, do not rely on natural-language taste alone. Apply the same concreteness expectation as `post_rules.concrete_detail_blockers()`.

- P1/P2, medical AI, governance, AI-tool, and business posts need at least `3` concrete anchors before they can stay review-eligible: source/artifact name, date, number, version, threshold, notification target, approver, re-check timing, log, stop condition, exception condition, input owner, evaluation window, or target metric
- those posts also need at least one operational action or check: who decides, what threshold is used, when to re-check, what gets logged, or what exception stops rollout
- P3 and career posts are not exempt from concreteness; they may stay reflective, but must include a concrete scene, decision, or next action
- vague endings such as `ここが重い論点です`, `最後に効きます`, `意味があります`, `そこが分岐点になる`, and `視点を正す一句だ` are blocked unless the preceding body already names the exact check item, owner, threshold, or source artifact
- metaphors are explanatory tools, not substitutes for evidence. If the metaphor becomes the main landing, rewrite toward a source-grounded or action-grounded paragraph

## Mandatory Preflight

Before any publish action, verify all of the following and state any mismatch:

1. Posting mode: `draft`, `approved`, or `manual immediate`
2. Schedule: if a slot like `22:00` was mentioned, confirm whether it should still be preserved
3. Body language: publish-facing `Body` / `Body JA` are Japanese-only. Fail if there is any English sentence, English CTA, English-first hashtag, or bilingual paragraph pair. Allow only unavoidable proper nouns, product names, source titles, URLs, API paths, and short technical tokens with Japanese context.
4. Quote handling: if this is a quote post, the X/Twitter status URL is in the body, `Source URLs` may preserve it as metadata, and `Reply URLs` does not duplicate it
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
10. Posting-lock state: whether the row is actually blocked by validation or is simply stuck in `Status=posting`
   If the row is `posting`, inspect `Locked By` and the embedded timestamp first. Treat `posting` older than 5 minutes as a recovery problem before changing text, image, or citations.
11. X upload size risk: whether the raw local image is likely to trip media upload even though thumbnail QA passed
   Check the actual local file size, not only `thumbnail_bytes`. If the image is above the X upload soft limit, rely on the runtime upload-safe re-encode path or replace the asset before concluding that the post is ready.
12. Reserved-slot compliance: if `Scheduled` is Monday/Thursday `06:50 JST`, verify note-lead mode, embedded public `note.com` URL, empty `Reply URLs`, and the `06:50` teaser cap before keeping the row scheduler-safe
13. Note-lead repair check: if you touched a `note.com` lead row, verify after sync that the URL is present in `Body` / `Body JA`, absent from `Reply URLs`, and that the row did not drift back into long-form summary
14. Recent-theme collision: compare the candidate against recent `posted.json` history and the latest posted Notion rows
   If the topic, thesis, and landing feel substantially the same, block or rewrite even when lexical similarity stays below the runtime threshold.

If any item is ambiguous, stop before posting.

For new draft generation, also verify:

15. body length target: whether this draft is intended to be schedulable later (`800-1500字`) or just a short ideation stub
    For note leads, also ask whether the copy is the shortest viable approved teaser or an over-explained summary.
16. title gate: title is Japanese, `15-30字`, non-placeholder, and expresses the post claim or reader bottleneck rather than only naming the source or tool
17. pillar/category/pattern mix: avoid overconcentrating on one pillar or one rhetorical pattern across a batch; before leaving rows `approved`, verify that `category` and `pattern` are both filled and that reserved note-lead slots stayed fixed during any rebalance
18. line-break rhythm and formula variety: whether the draft has a readable cadence rather than equal-sized walls of text, and whether it avoids repeated ordinal structures such as `第一に / 第二に / 第三に` unless the post truly needs a checklist
    Check paragraph lengths explicitly: no run of `3` or more adjacent body blocks over `70字` should sit within a `20字` band unless a legal/quote list genuinely requires it.
    Also check the GHA-backed runtime floor: dense body paragraphs should not exceed roughly `140字`, and paragraph groups should not exceed `3` sentences before a real break or pivot.
    Also check the sentence-line rule: each Japanese `。` normally ends the physical line, while blank lines appear only between rhetorical blocks.
19. tone balance: whether the draft avoids both hard-assertion streaks and over-polite filler
    For Japanese body copy, verify that `です/ます` is the default register, with plain-form and nominal endings reserved for hooks, pivots, and final emphasis.
20. semantic novelty: whether the candidate is truly a new take instead of a same-topic same-tone rewrite
    If it only paraphrases a recent post, reject it. Revisit only with a different angle, and reserve homage-style callbacks for posts that are months old.
21. Japanese-only language check: verify `language_ratio`, `english_sentence_count`, and allowed Latin-script terms. Any English sentence or English-first hashtag blocks approval; proper nouns and short technical tokens are allowed only inside Japanese sentences.
22. source reconstruction: for legal / regulatory / standards / government explainers, whether the draft states what the source actually changed or clarified before moving into abstract implications
23. concreteness gate: for schedulable drafts, verify the required concrete anchors and operational action. If the draft only says `AI時代`, `価値`, `責任`, `本質`, or `判断` without a concrete source, scene, threshold, owner, or next action, keep it in `draft` or rewrite it

## Notion Body Safety

`Body` and `Body JA` are candidate post text fields, not operator instruction fields.

- Do not put task instructions, scheduling notes, TODO text, or process commentary into `Body` / `Body JA`.
- If an X lead has not been written yet, leave `Body` and `Body JA` empty.
- Store instructions such as `create an X lead at 06:50`, audience, length, hashtag count, URL-card requirement, and non-posting constraints in `Draft Diff Memo` and/or `Schedule Override Reason`.
- For `note.com` lead rows, keep the note URL in `Source URLs` and `Candidate Trigger URL`, and include the public note URL in the final X body as a standalone URL for card rendering while keeping `Reply URLs` empty.
- For non-lead rows, include a note URL in the final X body only when it is intentionally meant to appear as a standalone URL card.
- For `note.com` lead rows, validate the value gate before `Status=approved`: ignore the standalone URL while counting value, normalize whitespace, and ensure at least 220 Japanese characters of standalone value. Keep the full body under 500 characters for Monday/Thursday `06:50 JST` reserved slots.
- Before setting `Status=approved`, read `Body` / `Body JA` as if they will be posted verbatim. If any operational sentence like `作成します`, `TODO`, `自動投稿なし`, `JSTに`, or `対象記事` remains, keep the row in `draft` and move that text to memo fields.

## Japanese-Only Language Gate

Apply this gate before presenting, syncing, approving, or posting x-auto copy.

- `language_ratio`: estimate whether the main reading experience is Japanese. Latin-script terms should be exceptions, not the body frame.
- `english_sentence_count`: count full English sentences. If it is greater than `0`, the row is not publish-ready.
- `allowed_latin_terms`: allow only unavoidable product names, source titles, organizations, standards, API paths, URLs, and short technical tokens such as `AI` or `API`.
- `has_english_cta_or_hashtag`: block English CTAs and English-first hashtags unless the tag is a fixed event or product name.
- `has_bilingual_pairing`: block Japanese/English duplicate paragraph pairs; write the point once in Japanese.
- do not demote a good Japanese draft just because it contains source names like `Claude Code`, `JAMA`, or `API`. The blocker is English prose, not every Latin character.

## Thumbnail Guard

If the request includes creating or replacing a thumbnail, or if the draft is being prepared as a complete x-auto candidate with image expectations, use `x-auto-thumbnail-art-director` alongside this skill.

If the thumbnail request uses content-marketing ad prompt examples, do not persist or replay the external prompt prose. Use only the shared thumbnail `contentMarketingAdGuidance` abstraction and keep x-auto article thumbnails no-CTA unless the row is explicitly an ad, LP, email, signage, or campaign creative.

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
- reject the image if its subject matter does not match the post body, even when the render quality is otherwise high
- for concrete medical, operational, legal, or workflow posts, require visible subject alignment instead of abstract symbolism unless the user explicitly asked for abstraction
- keep generation bounded: default budget is one 3-candidate pass plus at most one targeted retry batch
- if overlay text changed, regenerate and sync Notion before any post or repost
- if a posted tweet is later deleted manually, the thumbnail fix still must be reflected in the Notion row that owns the asset
- prefer `scripts/local/integrations/xauto-thumbnail-gen.js` as the ChatGPT Images 2.0-first generator entrypoint for x-auto assets
- require the project `DESIGN.md` gate for generation and replacement. Cursorvers defaults to `/Users/masayuki/Dev/cursorvers-inc/DESIGN.md`; override only with `XAUTO_THUMBNAIL_DESIGN_MD` or `CURSORVERS_DESIGN_MD` for a task-local contract.

This guard does not prescribe thumbnail style.

- do not force a single house template
- do not block abstract, symbolic, logo-led, collage, cropped, overpainted, or post-processed approaches if they improve quality
- but when the post is concrete, do block abstract or symbolic approaches that fail semantic alignment with the body
- do not treat local editing, compositing, cropping, or art-directed cleanup as non-compliant
- use this skill to protect publication integrity, not to narrow visual exploration
- when the user is optimizing image quality, prefer multiple visual directions and select the strongest render before syncing Notion
- after the bounded retry budget is exhausted, stop and summarize the blocker instead of silently spending more generation attempts

## Stopped-Post Triage

When a user says a post is "stopped", use this order:

1. Read the Notion row directly.
2. Check whether `Status` is `approved`, `failed`, or `posting`.
3. If it is `posting`, inspect `Locked By` and timestamp before touching the body or image.
4. If `posting` is older than 5 minutes, recover it first and only then inspect validation gates.
5. Prefer Notion SoT for stuck-post recovery. Do not rely on local queue state alone, because local cache can miss a row that is still `posting` in Notion.
6. If `Locked By` points to the local MBP or another non-designated host, treat that as a single-writer policy breach before anything else. Stop the prohibited local scheduler / launchd path first, then clear the dead lock.
7. Only after lock recovery should you decide whether the real blocker is text length, citations, thumbnail QA, duplicate blocking, or runtime failure.

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

## Quote Watchlist Reality

Do not assume new article sources or newly discussed accounts are automatically added to quote sourcing.

- `trend_scanner.py` uses a static `WATCH_ACCOUNTS` list
- `quote_candidates.json` is populated only from scans of those watched X accounts
- creating a normal article-based post, scheduling a Notion row, or setting `source_url` does not add a handle to the quote watchlist
- if the user wants a new account monitored for future quote posts, that is an explicit config change, not a side effect of drafting
- for future quote-post requests, ask whether the quoted poster should be promoted into `WATCH_ACCOUNTS` unless the user already made that intent explicit
- if the user already made that intent explicit, update the watchlist immediately and mention the handle you added
- if the user intentionally embeds a quote/link card, record the rhetorical pattern if useful and keep the row aligned with `PARITY::X_QUOTE_URL_BODY_EMBED=true`

## Session Failure That Triggered This Skill

This skill exists to prevent these exact mistakes:

- treating a scheduled `22:00` post as an immediate publish
- moving quote URLs out of body text into reply-only citation flow
- trusting a stale or conflicting instruction source over runtime behavior
- posting before confirming whether the previously deleted tweet was the canonical one
- changing a thumbnail after publication without first verifying visual layout
