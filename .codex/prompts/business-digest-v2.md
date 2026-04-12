# Business Digest v2 — Calendar + Tasks Integration

## Task

Implement the spec at `.fugue/pre-implement/business-digest-v2-spec.md`.

Target file: `~/.claude/hooks/business-digest.mjs`

## Summary

Add 2 new data sources to the existing Business Digest SessionStart hook:

1. **Calendar** — `gws calendar +agenda --today --format json` → show today's events
2. **Google Tasks** — `gws tasks tasks list --params '{"tasklist":"@default"}' --format json` → show pending tasks

Both use the existing `runWithTimeout()` + `Promise.allSettled()` pattern. No new dependencies.

## Implementation Checklist

- [ ] Add `fetchCalendar(config)` function
- [ ] Add `fetchTasks(config)` function
- [ ] Add both to `Promise.allSettled()` array (line 306)
- [ ] Extend `formatOutput()` signature to accept calendar + tasks
- [ ] Add calendar section (BEFORE gmail section, most time-sensitive)
- [ ] Add tasks section (AFTER overdue section)
- [ ] Tasks 403 → silent skip (API may not be enabled)
- [ ] Update `writeCache()` to include new sources
- [ ] Test: `node ~/.claude/hooks/business-digest.mjs`

## Constraints

- Do not change existing gmail/invoice/overdue/bookkeeping logic
- Maintain 15-second total timeout
- Always exit 0
- New fetchers must use `config.internal_timeout_ms` (6000ms)

## Verified CLI outputs

Calendar (working):
```json
{"count":3,"events":[{"calendar":"flux@cursorvers.com","end":"2026-03-23T10:30:00+09:00","start":"2026-03-23T10:00:00+09:00","summary":"Chrome DevTools MCP 運用レビュー"},{"calendar":"flux@cursorvers.com","end":"2026-03-23T19:00:00+09:00","start":"2026-03-23T18:00:00+09:00","summary":"株式会社Stylish 尾形様との面談"},{"calendar":"web会議・webinar(演者)","end":"2026-03-23T20:00:00+09:00","start":"2026-03-23T19:00:00+09:00","summary":"AOM案件導入オリエンテーション"}]}
```

Tasks (403 until API enabled — handle gracefully):
```json
{"error":{"code":403,"message":"Google Tasks API has not been used..."}}
```
