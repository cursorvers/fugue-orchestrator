# X-auto Note Linking Rule

- **Status**: Recorded
- **Date**: 2026-04-01
- **Owner**: masayuki

## Scope

This rule applies to `X Post Queue` entries that serve as lead posts for a `note.com` article.
The Notion database is the operational source of truth for these queue rows.
It does not override quote-post or reply-url flows; those are governed by `docs/agents/x-auto-contract.md`.

## Rule

1. The public `note.com` URL must be included in the main post body.
2. For bilingual queue rows, the same rule applies to both `Body` and `Body JA`.
3. `Source URLs` stores the canonical article URL used as the source reference.
4. A separate reply or thread URL is not assumed by default.
5. For rows targeting Monday or Thursday `06:50 JST`, treat the entry as a reserved-slot note lead:
   - keep the body in short teaser form
   - do not allow long-form article recap in the main body
   - reject the row as scheduler-safe if it exceeds the reserved-slot teaser cap (`< 500字`) or reads like a substitute for the article

## Verification Boundary

As of 2026-04-01, the repository-visible configuration supports the URL in the main body text and
does not define a separate reply-specific URL field for `X Post Queue`.
If a reply-thread URL rule is introduced later, document the schema and automation contract before
changing this rule.
