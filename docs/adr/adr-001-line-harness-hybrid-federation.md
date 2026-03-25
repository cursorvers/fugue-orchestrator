# ADR-001: LINE Harness OSS Hybrid Federation Integration

## Status

Accepted (2026-03-25)

## Context

Cursorvers' LINE integration is currently outbound-only (`line-notify.sh`, 625 lines) with an inbound webhook stub in an external repo (`cursorvers_line_free_dev`, status: stub-only). There is no CRM, no automation engine, and no friend management within the FUGUE orchestrator.

LINE Harness OSS (`Shudesu/line-harness-oss`, MIT License) provides a full-featured LINE CRM built on Cloudflare Workers + Hono + D1 with 143 API endpoints, event bus, IF-THEN automation engine, and multi-account management.

Three integration patterns were simulated in parallel:

| Pattern | Feasibility | Value | Risk |
|---------|:-----------:|:-----:|:----:|
| A: Webhook Bridge | 8 | 7 | 4 |
| B: SDK Tool Integration | 7 | 8 | 5 |
| C: Event Bus Federation | 7 | 8 | 6 |

## Decision

Adopt **Hybrid Federation** (Pattern A → C staged escalation):

- **Phase 1-2**: Webhook Bridge pattern for safe foundation
- **Phase 3-4**: Event Bus Federation for full bidirectional AI-CRM

### Key Design Decisions

1. **Deferred Reply Pattern**: `message_received` uses immediate `replyMessage` (free ACK) + async `pushMessage` (agent response) to handle LINE's 1-second timeout constraint
2. **Local-first boundary**: Deterministic rules stay in LINE Harness local automation; inference-dependent decisions escalate to FUGUE agents
3. **Multi-model diversity**: Codex (critical), GLM (lightweight), Gemini (visual) — trio preserved
4. **Existing coexistence**: `line-notify.sh` remains untouched for outbound delivery

## Constraints

- Existing `line-notify.sh` outbound delivery: zero impact
- Trio diversity (Codex + GLM + Gemini): no single-model degradation
- Cost ceiling: $7/month incremental
- All Layer 3 implementation: Codex/GLM delegation only

## Phased Rollout

| Phase | Scope | Risk | Kill Switch |
|-------|-------|------|-------------|
| 1 | LINE Harness standalone deploy (CF Workers) | None | Worker deletion |
| 2 | FUGUE Bridge shadow mode + `friend_add` cutover | Low | Webhook URL removal |
| 3 | `message_received` Deferred Reply | Medium | `FUGUE_LINE_FEDERATION_ENABLED=false` |
| 4 | Full federation (score, CV, campaigns) | Medium | Same as Phase 3 |

## Acceptance Criteria

1. Phase 2 shadow mode: 7 days, classification accuracy >99%, latency within budget
2. `friend_add` personalized response engagement >= existing template baseline
3. `message_received` perceived latency <10 seconds
4. LINE API quota consumption <80% of monthly allocation
5. Zero impact on existing `line-notify.sh` outbound delivery

## Consequences

### Positive

- LINE transforms from one-way broadcast to bidirectional AI-powered CRM
- Leverages existing CF Workers Hub webhook router patterns (Discord/Slack/Telegram)
- Kill switch at every phase ensures safe rollback
- Multi-model trio diversity preserved throughout

### Negative

- Deferred Reply pattern means 2 messages per interaction (ACK + response) for `message_received`
- Operational complexity of maintaining local automation rules + FUGUE agent routing in parallel
- External OSS dependency (mitigated by MIT license, ability to fork)

### Neutral

- LINE Harness remains a peripheral surface — control-plane truth stays in FUGUE
- `line-notify.sh` outbound path unchanged; consolidation is optional in Phase 4+
