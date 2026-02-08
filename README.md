# FUGUE Orchestrator

> **FUGUE** = **F**ederated **U**nified **G**overnance for **U**niversal **E**xecution
>
> Distributed autonomy x Unified convergence

A multi-model AI orchestration framework for Claude Code that delegates tasks to specialized AI agents (Codex/GPT, GLM, Gemini, Grok) while keeping Claude as a pure orchestrator.

The name draws from the musical fugue -- multiple independent voices weaving together into a unified whole. Each AI model is a voice; the orchestrator ensures harmony.

## Problem

Claude Code's Agent Teams feature introduces rate limits that are lower than expected. Running everything through Claude (subagents, planning, execution) burns through limits quickly.

## Solution

**2-Layer Orchestration**: Claude Opus acts solely as an orchestrator (routing, integration, reporting). All individual task execution is delegated to external models with fixed-cost subscriptions.

```
User
    |  instruction
Claude Opus (Orchestrator only)
    |  routing
+-----------------------------------+
| Execution Tier                    |
| +-> Codex (code, design, security)|
| +-> GLM   (review, summary, math) |
| +-> Gemini (UI/UX evaluation)     |
| +-> Grok  (X/Twitter, realtime)   |
| +-> Pencil MCP (UI development)   |
+-----------------------------------+
    |  artifacts
+-----------------------------------+
| Evaluation Tier (auto)            |
| +-> GLM   (code quality)          |
| +-> Codex (security audit)        |
| +-> Gemini (UI/UX audit)          |
+-----------------------------------+
    |  feedback
Claude Opus (integrate & report)
```

## Key Principles

- **Orchestrator never executes**: Claude routes, integrates, and reports. Never implements.
- **Fixed-cost maximization**: Codex ($200/mo) and GLM ($15/mo) handle 90%+ of tasks.
- **Subagent minimization**: Haiku/Sonnet subagents consume Claude rate limit. Only used for file exploration.
- **Dual-tier evaluation**: Artifacts pass through automated review before reporting to user.

## File Structure

```
CLAUDE.md                          <- Entry point (copy to ~/.claude/)
rules/
  delegation-matrix.md             <- SSOT: who handles what
  auto-execution.md                <- Auto-delegation triggers
  delegation-flow.md               <- How delegation works
  codex-usage.md                   <- Codex-specific guide
  dangerous-permission-consensus.md <- 3-party consensus for risky ops
  coding-style.md                  <- Code quality rules
  testing.md                       <- TDD rules
  security.md                      <- Security checklist
  performance.md                   <- Model selection & optimization
  secrets-management.md            <- API key management
```

## Prerequisites

| Service | Purpose | Cost |
|---------|---------|------|
| Claude Code (MAX plan) | Orchestrator | Subscription |
| OpenAI Codex / GPT Pro | Code execution, design, security | $200/mo |
| GLM-4.7 (ZhipuAI) | Lightweight review, summary, math | $15/mo |
| Gemini (Google AI) | UI/UX evaluation, image analysis | Pay-as-you-go |
| Grok (xAI) | X/Twitter, realtime info | API-based |

## Setup

1. Copy `CLAUDE.md` to `~/.claude/CLAUDE.md`
2. Copy `rules/` to `~/.claude/rules/`
3. Edit `CLAUDE.md` to customize the `[CONFIGURE]` sections
4. Set up delegation scripts (see `examples/`)
5. Configure API keys as environment variables

## Delegation Scripts

The framework expects delegation scripts at:
```
~/.claude/skills/orchestra-delegator/scripts/
  delegate.js        # Codex delegation
  delegate-glm.js    # GLM delegation
  delegate-gemini.js # Gemini delegation
  delegate-grok.js   # Grok delegation
  parallel-codex.js  # Parallel Codex execution
  consensus-vote.js  # 3-party consensus voting
```

See `examples/` for reference implementations.

## Rate Limit Strategy

| Model | Target Usage | Role |
|-------|-------------|------|
| **Codex** | 120-150 calls/week | All code tasks + design + complex decisions |
| **GLM** | 120-150 calls/week | All non-code tasks + light review + classification |
| **Subagent (Haiku)** | <=5 calls/week | File exploration only |
| **Subagent (Sonnet)** | 0 calls/week | Prohibited (use Codex instead) |
| **Claude Opus** | Minimal | Orchestration only |

## License

MIT

## Credits

Inspired by the FUGUE philosophy: Distributed autonomy x Unified convergence.
