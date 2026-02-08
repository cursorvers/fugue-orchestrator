# ADR-001: Why FUGUE Exists

**Status**: Accepted
**Date**: 2026-02-08
**Deciders**: FUGUE Orchestrator maintainers

## Context

Claude Code introduced Agent Teams (Opus 4.6), enabling multiple Claude instances to collaborate. However, Agent Teams consumes Claude rate limits per member, leading to frequent throttling during daily development workflows.

Existing multi-agent frameworks (AutoGen, CrewAI, LangGraph) solve multi-agent coordination but do not address:
1. **Rate limit economics** of a specific host platform (Claude Code)
2. **Fixed-cost subscription optimization** across multiple AI providers
3. **Governance-first design** where safety consensus is built into the routing layer

## Decision

Build FUGUE as a **governance layer** (not a framework) that:
- Keeps Claude Opus as a pure orchestrator (routing, integration, reporting)
- Delegates all task execution to external models with fixed-cost subscriptions
- Minimizes Claude API consumption to avoid rate limits

## Architecture: 2-Layer Orchestration

```
Layer 1: Codex  ($200/mo fixed) -> All code + design + security + complex decisions
Layer 2: GLM    ($15/mo fixed)  -> All non-code + review + summary + classification
```

### Why Not Use Existing Frameworks?

| Framework | Why FUGUE Differs |
|-----------|-------------------|
| **AutoGen** | Conversation-based; all agents consume the same LLM. FUGUE routes to the cheapest capable model per task. |
| **CrewAI** | Role-based teams; still runs on a single provider's API. FUGUE splits across providers to avoid single-provider rate limits. |
| **LangGraph** | Graph-based state machine; production-ready but generic. FUGUE is Claude Code-specific and opinionated about cost. |
| **Agent Teams** | Native Claude peer communication; powerful but rate-limit-heavy. FUGUE is the complement -- handle 95% externally, reserve Agent Teams for the 5% that needs direct member communication. |

### Why Opus as Orchestrator?

**Challenge identified in review**: "Using Opus purely for routing is financially inefficient" (GLM evaluation).

**Response**: On Claude MAX subscription, Opus usage is within fixed cost. The real constraint is rate limit, not price. Opus routing consumes minimal tokens per task (~200-500 for classification). The alternative (deterministic routing code) loses the ability to handle ambiguous task classification, which accounts for ~20% of real-world inputs.

**Trade-off accepted**: Opus is overkill for clear-cut routing. It earns its keep on ambiguous inputs and integration reporting.

## Consequences

### Positive
- Claude rate limit consumption reduced by ~90% (from 30-45 subagent calls/week to <=5)
- Fixed-cost models (Codex $200 + GLM $15) handle 90%+ of tasks
- Dual-tier evaluation catches quality issues before user sees results
- 3-party consensus prevents dangerous operation accidents

### Negative
- **Vendor lock-in**: Tightly coupled to Codex + GLM + Gemini capabilities
- **Setup friction**: 3 API keys + delegation scripts required
- **Latency**: External API round-trips add 2-30s per delegation
- **No runtime enforcement**: Governance is documentation-based, not code-enforced

### Risks
- If OpenAI changes Codex/GPT Pro pricing, Layer 1 economics break
- If ZhipuAI (GLM) has availability issues, Layer 2 needs fallback
- New Claude rate limit changes could make subagent prohibition unnecessary

## Alternatives Considered

### A. Pure Agent Teams (rejected)
- **Why rejected**: Rate limits hit within 1-2 hours of active development
- **When to reconsider**: If Anthropic significantly raises rate limits

### B. LangGraph + Multi-Provider (deferred)
- **Why deferred**: Adds runtime complexity; current governance-as-documentation approach is simpler
- **When to reconsider**: When the team needs programmatic routing, retry logic, or circuit breakers

### C. Single Model (rejected)
- **Why rejected**: No single model excels at all task types. GLM is better value for summaries; Codex is better for code; Gemini is better for visual evaluation.

## Review Schedule

Re-evaluate this decision when:
- Claude rate limits change significantly
- Codex/GPT Pro pricing changes
- A competing framework adds native cost-aware routing
- FUGUE usage exceeds 6 months without architecture changes
