---
name: note-manuscript
description: Write and iteratively refine long-form note.com manuscripts with first-source verification. Store process upgrades, not full past drafts.
metadata:
  short-description: note manuscript workflow
---

# note-manuscript

## Goal

Produce a high-quality note.com manuscript (typically 8,000-12,000 chars) with strong readability and strict primary-source verification.

## Non-goal

Do not persist full prior articles into the skill. Persist only reusable process improvements.

## Core workflow

0. Initiative rule for orchestrated writing
- Writing may be orchestrated with multiple lanes for fact-checking, counterarguments, source gathering, and editorial review.
- Even when lanes run in parallel, initiative for structure, thesis selection, and final wording should stay with one declared `lead_writer_lane`.
- Other lanes should challenge, verify, and sharpen the manuscript, but should not silently replace the lead narrative voice.
- If the lead writing lane is unavailable, times out, or misses the draft-step SLA, switch that writing lane to a predeclared backup lead and record `lead_override_reason`.
- Keep `active lanes >= 2` throughout the workflow. If the lane count drops below 2, pause and replenish lanes before continuing.

0.5 Team contract for substantial manuscript runs
- Use this team shape when the user asks for a strong article, multi-agent work, review simulation, or public note publication:
  - `Research-A`: audience pain, theme fit, survey/session notes, LP/seminar/user-voice material. Output `audience_theme_memo`.
  - `Research-B`: primary facts, industry/technical context, latest official data, competitive landscape. Output `fact_source_memo`.
  - `Research-C / Devil's Advocate`: objections, counterarguments, reader doubts, misuse/炎上 risk, weak assumptions. Output `risk_objection_memo`.
  - `Structure Lead`: merge A/B/C into thesis, angle, H2/H3 outline, evidence placement, and So What. Output `structure_plan`.
  - `Editor-in-Chief`: review the plan for logic, emotional pull, So What, novelty, and read-through force before drafting. Output `editor_review`.
  - `Writer`: draft from the approved structure and editor feedback. Output `manuscript_draft`.
  - `Final Reviewer`: decide publish readiness after QA and corrections. Output `final_review_summary`.
- Default phase order: parallel research -> structure plan -> editor review -> draft -> article QA -> correction loop -> final package.
- Reinject `Research-C / Devil's Advocate` before locking structure and before final readiness. Do not use critique only after the manuscript is already fixed.

0.6 Progress and slice contract
- For long-running or orchestrated runs, each work report must include `progress_pct`, `remaining_slices`, `current_gate`, `next_slice`, and `blockers`.
- Estimate progress by completed gates, not by elapsed time: constraints 10%, research lanes 25%, fact ledger 40%, structure approved 55%, draft complete 70%, QA/corrections 85%, publication package 95%, delivered 100%.
- A `slice` is one bounded plan/execute/review/fix cycle that produces a checkable artifact. Re-estimate remaining slices whenever an S0/S1 issue or source-gate failure appears.

1. Confirm deliverable constraints
- Target audience, length, tone (です・ます調 or である調), required sections, and output format.
- If missing, assume: note article, long-form, practical and evidence-first.
- If the user explicitly asks to match past note posts, inspect at least the requested number of published posts before rewriting. When no number is given, inspect 10-15 recent posts; when the user says `最低30投稿`, inspect at least 30 and record a compact style-analysis artifact rather than pasting full article text into context.
- For the `nice_wren7963` note account, house-style calibration should measure at minimum: TOC usage, glossary usage, numbered H2 patterns, FAQ/reference placement, average paragraph length, and tone distribution (`です/ます` vs `である/だ`).
- For body-style review, load `references/writingstyle.md` when the user asks for article review, house-style fit is uncertain, or no recent-post calibration is available. Treat it as a review rubric, not a replacement for user instructions or measured outlet style.
- If the user's worldview, beliefs, or author voice matters, read `~/.claude/docs/philosophy.md` before drafting instead of relying only on chat context or direct Obsidian reads.
- Treat `~/.claude/docs/philosophy.md` as the primary worldview source for writing. When this file exists, do not inspect Obsidian for worldview recovery during drafting.
- Use Obsidian only when `philosophy.md` is missing or when the user explicitly asks to refresh philosophy from Beliefs.
- Default refresh search order when Obsidian is explicitly needed:
  1) `$HOME/Obsidian Project Kit for Market/05_Beliefs`
  2) topic-relevant notes under `$HOME/my-vault-renew`
  3) other vaults only if the above are insufficient
- Read only a small, topic-relevant slice (typically 3-7 notes) and extract reusable stances, priorities, and taboo framings rather than copying prose.
- Restrict Obsidian reads to topic-relevant, author-safe material. By default, do not pull from private categories unrelated to the task, including family, health, unpublished client-sensitive notes, or personal logs unless the user explicitly asks for them.
- Do not quote philosophy or Obsidian prose verbatim into the manuscript by default; summarize it into a memo and use it as framing input only.

2. Build a fact ledger before drafting
- List every claim that could be time-sensitive or compliance-sensitive.
- Verify each claim against primary sources (official docs, laws/guidelines, vendor primary docs).
- Record date checked and source URL for each claim.
- Create a `claim_source_trace` before finalization with minimum fields: `claim_id`, manuscript location, claim text/summary, confirmed fact vs inference, source URL, access date, uncertainty, and pass/fail. The check passes only when every publishable factual claim is traced or explicitly labeled as inference.
- Keep a separate `author-philosophy memo` when `philosophy.md` or Obsidian was consulted. This memo is mandatory and should record `Adopted principles / Counter-belief / Reason for adoption / Framing impact`.
- Primary-source precedence is fixed: `Primary sources > philosophy.md > Obsidian beliefs > stylistic preference`. If worldview notes and primary sources conflict, follow primary sources and log the conflict explicitly instead of silently harmonizing it away.

3. Draft with fixed structure
- Use this order by default:
  1) グロッサリー
  2) 問題提起
  3) サービス/制度の一次情報比較
  4) 実務リスク
  5) 実装チェックリスト
  6) まとめ
- When matching `nice_wren7963` house style after calibration, prefer this publication order unless the user requests otherwise:
  1) 目次
  2) グロッサリー（用語集）
  3) 免責事項・利益相反開示
  4) はじめに
  5) 第1章...第N章
  6) FAQ
  7) おわりに / まとめ
  8) 参考文献
- Use explicit numbering in the TOC and section headings when the user asks for numbering or when past-post analysis shows numbered H2s are common. Keep numbering as navigation, not decoration.
- Keep sections scannable with short paragraphs and numbered lists.
- For public-facing note pieces, include at least one explicit authored thesis that goes beyond correct summary. The thesis should be grounded in primary sources and framed as a substantive insight rather than a provocative hot take.
- For note publication, add 3-5 embed placeholders during drafting, e.g. `[EMBED-1: primary source]`, so evidence and reading breaks are designed in rather than added ad hoc later.
- Assume a two-stage output when useful: a manuscript-first draft and a publication-optimized pass with shorter paragraphs, tighter headings, and better mobile scroll readability.

3.5 note editor structure pass (mandatory before draft upload)
- Before any note.com draft upload for the `nice_wren7963` publication profile, run a publication-structure pass modeled on the observed references:
  - `https://note.com/nice_wren7963/n/n7c9bf99e02ff`
  - `https://note.com/nice_wren7963/n/n323e2d757a50`
- This pass is mandatory even when the manuscript Markdown already reads well locally. Do not upload a plain manuscript-first layout directly unless the user explicitly asks for a raw draft.
- Use the following note-editor order by default:
  1) horizontal rule
  2) note table of contents block
  3) horizontal rule
  4) `## はじめに...` with the main problem frame
  5) a short bold thesis / core quote line
  6) horizontal rule
  7) `### グロッサリー...` and the legal/commentary disclaimer
  8) horizontal rule
  9) numbered or chaptered H2 body sections
  10) H3 chapter summaries titled `この章の要点です`
  11) FAQ
  12) summary / closing section
  13) `## 参考文献・引用一覧`
  14) hashtags as the final paragraph
- Use horizontal rules before major sections to create note-native visual rhythm. Avoid decorative separators inside dense lists.
- Use short bold core statements for thesis emphasis. Use blockquotes only when the article genuinely quotes a person/source or when the user explicitly wants quote-box styling.
- Keep H2/H3 only. Do not emit H1 in the body because note.com uses the title field separately.
- Remove process-only material from the upload body: title candidates, fact ledger, style analysis memo, embed placeholders that have not become actual note embeds, and thumbnail prompts.
- For source links that should render as note cards, use the note editor's external-article embed format when available; otherwise keep normal citations and the end reference list.

4. Perform staged refinement
- Stage A (technical): correctness, scope boundaries, contradiction removal.
- Stage B (editorial): readability, flow, term normalization, audience fit.
- Stage C (review): missing caveats, over-claims, citation gaps.
- Stage D (final): style consistency, typo pass, requirement compliance.
- Medium optimization such as paragraph shortening and heading tightening can start only after the claim/source trace is complete; publication media/layout optimization belongs after the article QA gate.
- In orchestrated writing, treat non-lead lanes as critic, verifier, and material-gathering lanes; final synthesis should preserve a single lead voice.

4.5 Article QA gate
- Run this gate after the first complete draft and after any material correction:
  - `existing_overlap_check`: overlap with past articles, repeated themes, and whether this draft adds a clear new value.
  - `question_check`: whether the opening question is answered, repeated questions are intentional, and each section resolves its promise.
  - `body_style_check`: tone consistency, overused endings, reader address, before/after framing, metaphor use, original terms, sentence length, and transition flow.
  - `trend_deep_dive_check`: freshness of the angle, recent official changes, stale data, shallow claims, and missing specialist context.
  - `structure_readability_check`: hook strength, H2/H3 order, section landing points, CTA/runway, examples, evidence, and term explanations.
  - `review_summary`: overall verdict, overlap/style/trend/structure verdicts, required fixes, optional fixes, publish readiness, and next action.
- Use severity tiers:
  - `S0`: unsupported factual/legal/compliance claim, broken primary source, privacy issue, or public-link leakage. Stop finalization.
  - `S1`: thesis not proven, article overlap without new value, major structure failure, or style mismatch for the target outlet. Rewrite and rerun the relevant gate.
  - `S2`: local readability, wording, formatting, or minor evidence-placement issue. Fix before final output when practical.
- Every `NG`, `needs_fix`, or `hold` verdict must include the exact issue, affected section, and concrete correction direction.
- If the user says `直して`, correct from the latest `review_summary`, then rerun at least `body_style_check`; rerun structure/trend/final readiness when the fix changes the thesis, section order, or factual claims.
- When changing this skill or using a newly changed gate for the first time, sanity-check the workflow against 2-3 cases in `references/validation-scenarios.md` before treating the gate as stable.

5. Enforce hard quality gates
- No unsupported factual statements.
- Distinguish inference vs confirmed fact.
- Keep policy/legal wording precise (quote minimally, paraphrase clearly).
- Ensure cited links are reachable at writing time.
- Prefer `curl -L -I` or equivalent live checks for every final reference URL. If an official URL returns 404 or repeatedly times out, replace it with a reachable primary-source URL before upload; do not leave a broken citation just to preserve citation count.
- For legal-adjacent topics, prefer phrasing such as `問題となり得る`, `実務上の差が出る`, `検討する意義がある` over categorical legal conclusions unless the user explicitly requests specialist analysis.
- When the topic touches law, regulation, or compliance, include a short statement that the piece is general commentary and not case-specific legal advice, unless the user explicitly asks for a different framing.
- Legal stop condition: if the user request requires `legality determination`, `regulatory interpretation conclusion`, or `action-permissibility advice`, stop drafting that part and output `general commentary only + escalate to qualified legal professional`.
- A failed `fact ledger`, `claim-source trace`, `legal stop condition`, or S0 article QA gate is a hard veto on finalization regardless of the lead writing lane.
- Gate order is fixed: `fact ledger complete` -> `claim-source trace check` -> `legal stop-condition check` -> `article QA gate` -> `note media optimization`.

6. Output package
- Final manuscript.
- Short assumptions note (only if needed).
- Source list with access date.
- For note-targeted pieces, prepare sources in two layers when useful: short in-text references for readability and a fuller end-of-article source list with access date.
- Before uploading a note draft, run the note preflight QC and fix all fail-closed items: target character count, citation count, no over-100-character sentences, no body-ending noun fragments, bullet punctuation, and H2/H3-only heading depth.
- Before uploading or re-saving a note draft through REST, check the body conversion output for excessive empty paragraph blocks. Keep author-intended line breaks and paragraph boundaries, but do not emit standalone blank-line blocks for every Markdown blank line unless the user explicitly wants extra vertical whitespace.
- For REST uploads, convert the note-editor structure intentionally: `[TOC]` must become a real note table-of-contents block, `---` or `* *` must become a horizontal rule, and adjacent short lines should be grouped with `<br>` inside a paragraph instead of creating an empty paragraph block for every Markdown blank line.
- If the current uploader cannot produce the note-editor structure above, create/use a structure-aware upload path for that run and record the script/path in the publishing package.
- If prior drafts will be deleted or the user asks to re-upload, create fresh note draft IDs and report the new edit URLs. Do not imply that an old draft was updated unless the upload script actually updated that same draft.
- For uploads with eyecatches, verify the edit URL resolves with authenticated access and record the draft ID, edit URL, local manuscript path, and local thumbnail path in a compact publishing package.
- When syncing a future X lead task into Notion, do not put workflow instructions into x-auto `Body` / `Body JA`. Leave those fields empty until the final X copy exists, and store scheduling or URL-card instructions in memo fields such as `Draft Diff Memo` or `Schedule Override Reason`.
- Treat note.com share preview links (`https://note.com/preview/<id>?prev_access_key=...`) as private review links, not public article links. They may be used to verify the draft content and extract the note ID, but the preview URL and access key must not appear in X lead body text, source fields, publication notes, or public-facing copy.
- When the default account is known, derive the expected canonical URL from the preview ID as `https://note.com/nice_wren7963/n/<id>` for draft planning, then live-check that canonical URL after publication before scheduling or approving the X lead.
- For x-auto `note.com` lead rows, check the runtime note-lead value gate before approval: after removing URLs and normalizing whitespace, the post body should have at least 220 Japanese characters of standalone value while staying under the reserved-slot cap. A teaser shorter than that may be reverted from `approved`.
- After publication or final user-provided screenshot review, record at least 5 draft-to-publication differences if the completion form materially differs from the draft.
- Promote a draft-to-publication difference into a reusable rule only after it recurs across multiple pieces, not from a single successful article.

## Thumbnail and media handoff rules

- Treat note thumbnails and X thumbnails as different targets. Do not reuse one size policy blindly.
- For note article eyecatches in the current workspace, preserve the approved `note-work` canvas when present: `1424x752` (ratio about 1.894). Do not crop the left or right side unless the user explicitly approves a crop.
- If the user rejects or discards a thumbnail, record it as a negative constraint in the local publishing package and do not surface it again as a candidate.
- If the user asks to use an approved NB2/Manus source image, preserve the exact source canvas unless only metadata or compression changes are required for upload.
- Do not claim that Manus/NB2 generated an image or that a file exists unless the local path, generation receipt, or upload output has been verified.
- When text is part of a thumbnail, pass the exact article title or user-approved title lines to the image-generation prompt. Verify after generation that title text is not cut off before uploading.
- For note eyecatches, treat `1424x752` as a fixed canvas contract unless the user explicitly changes it. Never crop left/right to fit a generated image; if resizing is unavoidable, pad or regenerate instead of trimming.
- When a user provides a reference thumbnail, extract reusable composition only (for example: centered person, arms extended, large overlapping headline, deep editorial background). Do not copy distinctive artifacts from the reference such as background numbers, exact copy, layout labels, or brand-specific decoration unless the user explicitly requests them.
- If the title must appear in multiple lines, preserve every approved line exactly. Avoid thumbnail helper paths that summarize, rewrite, or truncate title lines; bypass prompt enhancers when exact line count is critical.
- For Japanese text in thumbnails, prefer `Noto Sans JP` heavy weights. If the image model corrupts Japanese text, generate or use a clean visual background and composite the text locally with `Noto Sans JP` rather than accepting garbled model text.
- Before uploading a note eyecatch, perform a visual gate: dimensions are exactly correct, no left/right crop, main subject remains present if requested, all approved title lines are visible, no placeholder labels such as `subCopy`, no unintended numbers/percentages/UI text, and no reference-image artifacts. Reject or regenerate before upload if any gate fails.

## Publication profile

- Default note publication account for this workspace: `https://note.com/nice_wren7963` (`Cursorvers株式会社｜大田原 正幸｜医師・Founder`).
- When drafting for note publication and the user does not specify another destination, assume this account is the target outlet.
- Match this outlet's observed headline patterns before proposing titles:
  - long-form explanatory titles are acceptable
  - lead with a framed thesis or topic marker such as `〖...〗` or `『...』` when it improves scannability
  - prefer `何が変わるのか / なぜ重要か / どう読むべきか` style framing over blunt clickbait
  - favor titles that combine topic + meaning-making, not topic alone
- Treat this as a house-style default, not a hard rule. If the user requests a different tone or outlet, follow the user.

## Process-upgrade memory (what to keep in this skill)

When a manuscript is improved, append only reusable deltas:
- Better verification order.
- Better conflict-resolution rules for inconsistent sources.
- Better section templates / checklist items.
- Better phrasing constraints (what to avoid / what works).

Never append:
- Full article body.
- Private/sensitive user content.
- Time-locked conclusions without re-verification instructions.

Reusable deltas from 2026-04 note draft run:
- For `nice_wren7963` style matching, a 30+ post sample gives a more reliable house style than intuition. The observed reusable pattern was: TOC, glossary, numbered chapters, FAQ, references, short paragraphs, and predominantly `です/ます` tone.
- Keep style-analysis artifacts compact and metric-based. Good fields are checked count, common H2s, title patterns, average paragraph length, and tone counts.
- For final `nice_wren7963` note draft uploads, create a publication-structured copy separate from the workspace manuscript: top horizontal rule, TOC block, opening H2, bold thesis, glossary/disclaimer, H3 `この章の要点です`, FAQ, closing summary, references, final hashtags, and no process-only artifacts in the body.
- In note REST conversion, Markdown blank lines are structural hints, not literal empty note blocks. Preserve visual rhythm while avoiding accidental empty paragraph spam.
- Treat preflight QC output as the readiness gate; live-check final official URLs after edits, especially when replacing or renumbering PDF citations.
- Thumbnail provenance matters as much as image quality: preserve the approved canvas, keep negative/positive candidate lists, pass exact title lines, and run the visual gate before upload.
- For x-auto note leads, `Body` is final public post copy only. Keep workflow instructions out, keep preview access keys private, and run the runtime note-lead value gate before approval.
- When the user reports spacing or copy issues, identify the target artifact first: note body, publication preview, X lead, or scheduler row.

## Conflict-resolution rules

This skill inherits orchestration precedence from the nearest repository `AGENTS.md`. If this file conflicts with that document on orchestration rules, follow `AGENTS.md`; for manuscript quality gates and publish-readiness vetoes, follow this skill unless `AGENTS.md` is stricter.

When sources disagree:
1. Prefer newest official primary source.
2. If scope differs (plan/region/feature), state that explicitly.
3. If unresolved, present both possibilities and mark uncertainty.

## Writing defaults

- Prioritize concrete statements over abstract claims.
- Use plain explanations for technical terms.
- Avoid slogan-like language and overconfident phrasing.
- Keep clinical/compliance context explicit when relevant.
- Correctness alone is not enough for public writing. Add a clear authored opinion when the format calls for it, but keep it anchored to primary sources and avoid avant-garde or contrarian-for-its-own-sake framing.
