#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULE_DOC="${ROOT_DIR}/docs/x-auto-note-linking-rule.md"
ADR_DOC="${ROOT_DIR}/docs/ADR-005-x-article-defer-note-consolidation.md"

[[ -f "${RULE_DOC}" ]]
[[ -f "${ADR_DOC}" ]]

grep -Fq 'The public `note.com` URL must be included in the main post body.' "${RULE_DOC}"
grep -Fq 'the same rule applies to both `Body` and `Body JA`.' "${RULE_DOC}"
grep -Fq '`Source URLs` stores the canonical article URL used as the source reference.' "${RULE_DOC}"
grep -Fq 'A separate reply or thread URL is not assumed by default.' "${RULE_DOC}"
grep -Fq 'X投稿 → note記事リンクの誘導パターンを標準化' "${ADR_DOC}"

echo "x-auto note linking rule check passed"
