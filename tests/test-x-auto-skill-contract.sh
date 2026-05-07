#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DOC="${ROOT_DIR}/docs/agents/x-auto-contract.md"
NOTE_RULE_DOC="${ROOT_DIR}/docs/x-auto-note-linking-rule.md"
POST_GUARD_SKILL="${ROOT_DIR}/skills/x-auto-post-guard/SKILL.md"
THUMBNAIL_SKILL="${ROOT_DIR}/skills/x-auto-thumbnail-art-director/SKILL.md"
XAUTO_THUMBNAIL_GEN="${ROOT_DIR}/scripts/local/integrations/xauto-thumbnail-gen.js"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

[[ -f "${CONTRACT_DOC}" ]]
[[ -f "${NOTE_RULE_DOC}" ]]
[[ -f "${POST_GUARD_SKILL}" ]]
[[ -f "${THUMBNAIL_SKILL}" ]]
[[ -f "${XAUTO_THUMBNAIL_GEN}" ]]
grep -Fq 'XAUTO_THUMBNAIL_MANUS_CLIENT_PATH' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq '../claude-config/assets/skills/slide/scripts/manus-api-client.js' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'THUMBNAIL_DOCTRINE_AUTHORITY' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'thumbnail-gen/policy.md' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'prompt-library.json' "${XAUTO_THUMBNAIL_GEN}"

grep -Fq '### Lead-post note link' "${CONTRACT_DOC}"
grep -Fq '### Quote-post body-embed flow' "${CONTRACT_DOC}"
grep -Fq 'PARITY::X_QUOTE_URL_BODY_EMBED=true' "${CONTRACT_DOC}"
grep -Fq 'Quote-style posts may still attach a compliant thumbnail image' "${CONTRACT_DOC}"
grep -Fq '## Thumbnail Doctrine Authority' "${CONTRACT_DOC}"
grep -Fq 'thumbnail-gen/policy.md' "${CONTRACT_DOC}"
grep -Fq 'prompt-library.json' "${CONTRACT_DOC}"
grep -Fq 'shared still-image prompt doctrine' "${CONTRACT_DOC}"
grep -Fq 'provider-order doctrine' "${CONTRACT_DOC}"
grep -Fq 'Default posting mode is `draft`' "${CONTRACT_DOC}"
grep -Fq 'sole editable source of truth' "${CONTRACT_DOC}"
grep -Fq 'next sync must reflect that Notion value' "${CONTRACT_DOC}"
grep -Fq 'must not overwrite a newer Notion field value' "${CONTRACT_DOC}"
grep -Fq 'Automated candidate generation may create only new `draft` rows' "${CONTRACT_DOC}"
grep -Fq 'Candidate drafts must carry explicit provenance metadata' "${CONTRACT_DOC}"
grep -Fq 'Fixed scheduler slots are `06:50`, `11:50`, `16:50`, and `21:00` JST' "${CONTRACT_DOC}"
grep -Fq 'Monday and Thursday `06:50` are reserved' "${CONTRACT_DOC}"
grep -Fq 'metadata drift' "${CONTRACT_DOC}"
grep -Fq 'legacy launchd paths or `Documents` mirrors' "${CONTRACT_DOC}"
grep -Fq 'page-ID verification as canonical' "${CONTRACT_DOC}"
grep -Fq 'Thumbnail text layout is part of message quality' "${CONTRACT_DOC}"
grep -Fq 'same polite upper-left card' "${CONTRACT_DOC}"
grep -Fq '800-1500字' "${CONTRACT_DOC}"
grep -Fq 'Default publish-facing draft language is Japanese-only' "${CONTRACT_DOC}"
grep -Fq 'English clauses, connective phrases, and stylistic flourishes are a review blocker' "${CONTRACT_DOC}"
grep -Fq 'do not collapse the body into abstract commentary before reconstructing the concrete change' "${CONTRACT_DOC}"
grep -Fq 'If the source is not actually a statute or amendment, say so plainly' "${CONTRACT_DOC}"
grep -Fq '## Long-Form Line-Break Rhythm' "${CONTRACT_DOC}"
grep -Fq 'optimize paragraph breaks for scanability on X' "${CONTRACT_DOC}"
grep -Fq 'Use a Japanese title of `15-30字` by default' "${CONTRACT_DOC}"
grep -Fq 'put a line break after each Japanese full stop `。`' "${CONTRACT_DOC}"
grep -Fq 'Use a blank line only when the rhetorical block changes' "${CONTRACT_DOC}"
grep -Fq 'hosted CI run `24547016917`' "${CONTRACT_DOC}"
! grep -Fq 'English-default' "${CONTRACT_DOC}"
grep -Fq 'docs/agents/x-auto-contract.md' "${POST_GUARD_SKILL}"
grep -Fq 'manual immediate publish' "${POST_GUARD_SKILL}"
grep -Fq 'Runtime target: which live x-auto runtime is authoritative right now' "${POST_GUARD_SKILL}"
grep -Fq 'Metadata drift: whether the failure is truly missing assets vs stale QA flags' "${POST_GUARD_SKILL}"
grep -Fq 'Long-form line breaks are part of quality' "${POST_GUARD_SKILL}"
grep -Fq 'Publish-facing body copy is Japanese-only' "${POST_GUARD_SKILL}"
grep -Fq 'publish-facing `Body` / `Body JA` are Japanese-only' "${POST_GUARD_SKILL}"
grep -Fq 'title is part of the post contract, not an internal memo' "${POST_GUARD_SKILL}"
grep -Fq 'use a Japanese title of `15-30字` by default' "${POST_GUARD_SKILL}"
grep -Fq 'Sentence-line rule' "${POST_GUARD_SKILL}"
grep -Fq 'put a line break after each Japanese full stop `。`' "${POST_GUARD_SKILL}"
grep -Fq 'use a blank line only when the rhetorical block changes' "${POST_GUARD_SKILL}"
grep -Fq 'hosted CI run `24547016917`' "${POST_GUARD_SKILL}"
grep -Fq 'hosted GitHub Actions evidence covers the Japanese-only prompt' "${POST_GUARD_SKILL}"
! grep -Fq 'Japanese-only posting contract verified by hosted GitHub Actions' "${POST_GUARD_SKILL}"
! grep -Fq 'English-default' "${POST_GUARD_SKILL}"
grep -Fq 'line-break rhythm and formula variety: whether the draft has a readable cadence' "${POST_GUARD_SKILL}"
grep -Fq '800-1500字' "${POST_GUARD_SKILL}"
grep -Fq 'Primary-source delta reconstruction rule' "${POST_GUARD_SKILL}"
grep -Fq 'do not default to abstract summary first' "${POST_GUARD_SKILL}"
grep -Fq 'verify whether the event is an actual `制定` / `改正` or only a `公表` / `とりまとめ` / `解釈整理`' "${POST_GUARD_SKILL}"
grep -Fq 'source reconstruction: for legal / regulatory / standards / government explainers' "${POST_GUARD_SKILL}"
grep -Fq 'Runtime Triage Addendum' "${POST_GUARD_SKILL}"
grep -Fq 'xauto-thumbnail-gen.js' "${POST_GUARD_SKILL}"
grep -Fq 'docs/agents/x-auto-contract.md' "${THUMBNAIL_SKILL}"
grep -Fq 'shared generation doctrine' "${THUMBNAIL_SKILL}"
grep -Fq 'thumbnail-gen/policy.md' "${THUMBNAIL_SKILL}"
grep -Fq 'authoritative and newer than this adapter' "${THUMBNAIL_SKILL}"
grep -Fq 'kawaii systems' "${THUMBNAIL_SKILL}"
grep -Fq 'at least 3 visual directions' "${THUMBNAIL_SKILL}"
grep -Fq 'interactive/manual Codex sessions' "${THUMBNAIL_SKILL}"
grep -Fq 'Codex built-in `gpt-image-2`' "${THUMBNAIL_SKILL}"
grep -Fq 'ChatGPT Images 2.0 via API first, then Manus, then NB2' "${THUMBNAIL_SKILL}"
grep -Fq 'treat text placement as one of the main variation axes' "${THUMBNAIL_SKILL}"
grep -Fq 'Edge stack' "${THUMBNAIL_SKILL}"
grep -Fq 'Artifact and goal: create a 16:9 premium editorial thumbnail background for a Japanese X post.' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'Composition zones:' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'Typography intent:' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'Project DESIGN.md context:' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'XAUTO_THUMBNAIL_DESIGN_MD' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'DEFAULT_CURSORVERS_DESIGN_PATH' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'CURSORVERS_DESIGN_MD' "${XAUTO_THUMBNAIL_GEN}"
grep -Fq 'Negative constraints:' "${XAUTO_THUMBNAIL_GEN}"
! grep -Fq '/Users/' "${POST_GUARD_SKILL}"
! grep -Fq '/Users/' "${THUMBNAIL_SKILL}"
! grep -R -Fq --include='xauto_*' 'sync_post_image.py' "${ROOT_DIR}/scripts/local"
grep -Fq 'It does not override quote-post' "${NOTE_RULE_DOC}"

if node "${XAUTO_THUMBNAIL_GEN}" \
  --output "${TMP_DIR}/invalid-provider.png" \
  --title 't' \
  --subtitle 's' \
  --prompt 'p' \
  --provider 'codex' \
  >/tmp/xauto-invalid-provider.out 2>/tmp/xauto-invalid-provider.err; then
  echo "expected invalid provider to fail"
  exit 1
fi
grep -Fq '"success":false' /tmp/xauto-invalid-provider.out
grep -Fq "Invalid provider 'codex'" /tmp/xauto-invalid-provider.out

cat >"${TMP_DIR}/DESIGN.md" <<'EOF_DESIGN'
---
name: ContractTest
colors:
  primary: "#123456"
  accent: "#fedcba"
typography:
  headline:
    fontFamily: Noto Sans JP
    fontSize: 48px
spacing:
  md: 16px
rounded:
  sm: 4px
---

## Overview
Editorial system for readable Japanese thumbnails.

## Do's and Don'ts
- Do keep text zones clean.
- Don't add CTA buttons unless the row is explicitly an ad.

## Private Notes
DO_NOT_LEAK_THIS_PRIVATE_SECTION
EOF_DESIGN

node "${XAUTO_THUMBNAIL_GEN}" \
  --output "${TMP_DIR}/design-dry-run.png" \
  --title '設計テスト' \
  --subtitle '短い副題' \
  --prompt 'project context prompt' \
  --provider 'auto' \
  --design "${TMP_DIR}/DESIGN.md" \
  --dry-run >"${TMP_DIR}/xauto-design-dry-run.json"

node -e '
const fs = require("node:fs");
const payload = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!payload.success || !payload.dryRun) throw new Error("dry-run failed");
if (payload.designContextPath !== process.argv[2]) throw new Error("design path not reflected");
if (!payload.designContextHasTokens) throw new Error("design tokens not detected");
for (const needle of ["color.primary=#123456", "type.headline.fontFamily=Noto Sans JP", "Do keep text zones clean."]) {
  if (!payload.prompt.includes(needle)) throw new Error(`missing design prompt needle: ${needle}`);
}
for (const forbidden of ["DO_NOT_LEAK_THIS_PRIVATE_SECTION", "---\\nname: ContractTest", "## Private Notes"]) {
  if (payload.prompt.includes(forbidden)) throw new Error(`leaked forbidden design content: ${forbidden}`);
}
' "${TMP_DIR}/xauto-design-dry-run.json" "${TMP_DIR}/DESIGN.md"

node "${XAUTO_THUMBNAIL_GEN}" \
  --output "${TMP_DIR}/default-design-dry-run.png" \
  --title 'Junior AI' \
  --subtitle '採用します。' \
  --prompt 'Cursorvers recruitment banner' \
  --provider 'auto' \
  --dry-run >"${TMP_DIR}/xauto-default-design-dry-run.json"

node -e '
const fs = require("node:fs");
const path = require("node:path");
const payload = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const expected = path.resolve(process.argv[2]);
if (!payload.success || !payload.dryRun) throw new Error("default design dry-run failed");
if (payload.designContextPath !== expected) throw new Error(`default design path not reflected: ${payload.designContextPath}`);
if (!payload.designContextHasTokens) throw new Error("default design tokens not detected");
for (const needle of ["color.dark=#05070A", "dark high-contrast variant", "HGtOzDCaEAAIPBR.jpeg"]) {
  if (!payload.prompt.includes(needle)) throw new Error(`missing default design prompt needle: ${needle}`);
}
' "${TMP_DIR}/xauto-default-design-dry-run.json" "${ROOT_DIR}/../cursorvers-inc/DESIGN.md"

echo "x-auto skill contract check passed"
