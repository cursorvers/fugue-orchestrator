#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DOC="${ROOT_DIR}/docs/agents/x-auto-contract.md"
NOTE_RULE_DOC="${ROOT_DIR}/docs/x-auto-note-linking-rule.md"
POST_GUARD_SKILL="${ROOT_DIR}/skills/x-auto-post-guard/SKILL.md"
THUMBNAIL_SKILL="${ROOT_DIR}/skills/x-auto-thumbnail-art-director/SKILL.md"
XAUTO_THUMBNAIL_GEN="${ROOT_DIR}/scripts/local/integrations/xauto-thumbnail-gen.js"

[[ -f "${CONTRACT_DOC}" ]]
[[ -f "${NOTE_RULE_DOC}" ]]
[[ -f "${POST_GUARD_SKILL}" ]]
[[ -f "${THUMBNAIL_SKILL}" ]]
[[ -f "${XAUTO_THUMBNAIL_GEN}" ]]

grep -Fq '### Lead-post note link' "${CONTRACT_DOC}"
grep -Fq '### Quote-post or reply-url flow' "${CONTRACT_DOC}"
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
grep -Fq '## Long-Form Line-Break Rhythm' "${CONTRACT_DOC}"
grep -Fq 'optimize paragraph breaks for scanability on X' "${CONTRACT_DOC}"
grep -Fq 'docs/agents/x-auto-contract.md' "${POST_GUARD_SKILL}"
grep -Fq 'manual immediate publish' "${POST_GUARD_SKILL}"
grep -Fq 'Runtime target: which live x-auto runtime is authoritative right now' "${POST_GUARD_SKILL}"
grep -Fq 'Metadata drift: whether the failure is truly missing assets vs stale QA flags' "${POST_GUARD_SKILL}"
grep -Fq 'Long-form line breaks are part of quality' "${POST_GUARD_SKILL}"
grep -Fq 'line-break rhythm: whether the draft has a readable cadence' "${POST_GUARD_SKILL}"
grep -Fq '800-1500字' "${POST_GUARD_SKILL}"
grep -Fq 'Runtime Triage Addendum' "${POST_GUARD_SKILL}"
grep -Fq 'xauto-thumbnail-gen.js' "${POST_GUARD_SKILL}"
grep -Fq 'docs/agents/x-auto-contract.md' "${THUMBNAIL_SKILL}"
grep -Fq 'kawaii systems' "${THUMBNAIL_SKILL}"
grep -Fq 'at least 3 visual directions' "${THUMBNAIL_SKILL}"
grep -Fq 'treat text placement as one of the main variation axes' "${THUMBNAIL_SKILL}"
grep -Fq 'Edge stack' "${THUMBNAIL_SKILL}"
! grep -Fq '/Users/' "${POST_GUARD_SKILL}"
! grep -Fq '/Users/' "${THUMBNAIL_SKILL}"
! grep -R -Fq --include='xauto_*' 'sync_post_image.py' "${ROOT_DIR}/scripts/local"
grep -Fq 'It does not override quote-post or reply-url flows' "${NOTE_RULE_DOC}"

echo "x-auto skill contract check passed"
