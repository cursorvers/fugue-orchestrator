# 3-Party Consensus: andrej-karpathy-skills Evaluation

> **Date**: 2026-05-01
> **Source**: https://x.com/sharbel/status/2042914348859867218
> **Target**: [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) (13k+ stars)
> **Consensus Parties**: Claude Opus (orchestrator) + Codex philosophy + opencode philosophy

## Subject

CLAUDE.md behavioral guidelines derived from Andrej Karpathy's LLM coding failure observations. Four principles:

1. **Think Before Coding** -- state assumptions, present alternatives, surface confusion
2. **Simplicity First** -- minimum code, no speculative features, 200-line-to-50-line test
3. **Surgical Changes** -- touch only what's needed, match existing style
4. **Goal-Driven Execution** -- define success criteria, loop until verified

## Votes

| Party | Vote | Rationale |
|-------|------|-----------|
| **Claude Opus** (orchestrator) | **partial** | Principles 1,4 useful as delegation prompt template; 2,3 already covered by Claude Code system prompt. Full merge is token waste + "May I?" prohibition conflict. |
| **Codex** (sovereign executor) | **partial** | CODEX.md already has "smallest concrete change", "reject speculative redesign" -- principles 2,3 are redundant. Principles 1,4 add value as pre-task protocol (assumption declaration + success criteria). |
| **opencode** (multi-provider specialist) | **partial** | Content is vendor-neutral and portable across models. Should be reformulated as shared agent principles, not CLAUDE.md-specific. 200-line threshold needs alignment with FUGUE's 800-line max. |

## Consensus Result: PARTIAL ADOPT (3/3 unanimous)

All three parties agree on partial adoption. Specific overlap:

### Adopt (Principles 1 + 4 essence)

Add to delegation protocol (not Claude self-behavior):

```
Delegation template required fields:
(a) Assumptions stated explicitly
(b) Success criteria defined
(c) Verification steps specified
```

### Reject (Principles 2 + 3)

- **Simplicity First**: Already in Claude Code system prompt ("Don't add features beyond what the task requires") and CODEX.md ("reject speculative redesign"). Double-stating dilutes priority.
- **Surgical Changes**: Already in Claude Code system prompt ("Don't add error handling for scenarios that can't happen") and CODEX.md ("smallest concrete change"). Redundant.

## Critical Notes

- **Authority chain**: Karpathy's personal observations -> forrestchang's CLAUDE.md -> star count is not validation. No empirical evidence of behavior improvement.
- **FUGUE conflict**: "Think Before Coding" encourages clarification questions, which conflicts with CLAUDE.md prohibition on "May I...?" confirmations. Resolved by scoping to delegation prompts (Codex/opencode ask, not Claude).
- **Vendor neutrality**: opencode correctly notes CLAUDE.md naming creates false vendor dependency. If adopted, place in `AGENTS.md` or shared `AGENT_PRINCIPLES.md`, not in Claude-specific config.
- **Token cost**: Full 4-principle merge = ~300-500 tokens/request. Partial (delegation template only) = <50 tokens.

## Recommended Implementation

Single line addition to `CLAUDE.md` section 3 (FUGUE Architecture), under delegation matrix:

```markdown
### Delegation Prompt Template (required)
Every task delegated to Codex/GLM/opencode must include: (a) explicit assumptions, (b) success criteria, (c) verification steps.
```

## Environment Note

Evaluated in web sandbox without FUGUE runtime (codex/opencode CLIs unavailable). Consensus simulated via Claude subagents with party-specific philosophy constraints. For authoritative FUGUE consensus, re-execute on Mac mini with live kernel.
