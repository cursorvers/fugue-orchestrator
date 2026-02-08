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
CLAUDE.md                              <- Entry point (copy to ~/.claude/)
rules/
  delegation-matrix.md                 <- SSOT: who handles what
  auto-execution.md                    <- Auto-delegation triggers
  delegation-flow.md                   <- How delegation works
  codex-usage.md                       <- Codex-specific guide
  dangerous-permission-consensus.md    <- 3-party consensus for risky ops
  coding-style.md                      <- Code quality rules
  testing.md                           <- TDD rules
  security.md                          <- Security checklist
  performance.md                       <- Model selection & optimization
  secrets-management.md                <- API key management
examples/
  delegate-stub.js                     <- Minimal delegation script (Codex/GLM/Gemini)
  parallel-delegation.sh               <- Parallel code-review + security-audit
  consensus-vote-stub.sh               <- 3-party consensus voting demo
docs/
  ADR-001-why-fugue.md                 <- Architecture Decision Record: why FUGUE exists
```

## Prerequisites

| Service | Purpose | Cost |
|---------|---------|------|
| Claude Code (MAX plan) | Orchestrator | Subscription |
| OpenAI Codex / GPT Pro | Code execution, design, security | $200/mo |
| GLM-4.7 (ZhipuAI) | Lightweight review, summary, math | $15/mo |
| Gemini (Google AI) | UI/UX evaluation, image analysis | Pay-as-you-go |
| Grok (xAI) | X/Twitter, realtime info | API-based |

## Quick Start

```bash
# 1. Clone
git clone https://github.com/cursorvers/fugue-orchestrator.git
cd fugue-orchestrator

# 2. Copy rules to Claude Code config
cp CLAUDE.md ~/.claude/CLAUDE.md
cp -r rules/ ~/.claude/rules/

# 3. Set API keys
export OPENAI_API_KEY="your-openai-key"
export GLM_API_KEY="your-glm-key"
export GEMINI_API_KEY="your-gemini-key"

# 4. Test delegation (uses examples/delegate-stub.js)
node examples/delegate-stub.js -a code-reviewer -t "Review this function" -p glm

# 5. Test parallel evaluation
chmod +x examples/parallel-delegation.sh
./examples/parallel-delegation.sh "Review auth module" src/auth.ts

# 6. Test consensus voting
chmod +x examples/consensus-vote-stub.sh
./examples/consensus-vote-stub.sh "rm -rf ./build" "Clean build artifacts"
```

## Delegation Scripts

The `examples/` directory provides stub implementations you can use as starting points:

| Script | Purpose | Providers |
|--------|---------|-----------|
| `delegate-stub.js` | Single delegation to any provider | Codex, GLM, Gemini |
| `parallel-delegation.sh` | Parallel code-review + security-audit | GLM + Codex |
| `consensus-vote-stub.sh` | 3-party consensus for dangerous ops | Claude + Codex + GLM |

For production use, copy these to `~/.claude/skills/orchestra-delegator/scripts/` and customize:
```
~/.claude/skills/orchestra-delegator/scripts/
  delegate.js        # Based on delegate-stub.js -p codex
  delegate-glm.js    # Based on delegate-stub.js -p glm
  delegate-gemini.js # Based on delegate-stub.js -p gemini
  parallel-codex.js  # Based on parallel-delegation.sh
  consensus-vote.js  # Based on consensus-vote-stub.sh
```

## Architecture Decision

See [ADR-001: Why FUGUE Exists](docs/ADR-001-why-fugue.md) for the full rationale, including comparison with AutoGen, CrewAI, LangGraph, and Agent Teams.

## FUGUE Orchestration vs. Claude Code Agent Teams

FUGUE and Agent Teams are complementary, not competing. The key difference is **where computation happens** and **what consumes rate limits**.

### Fundamental Difference

|  | FUGUE Orchestration | Agent Teams |
|--|---------------------|-------------|
| **Executors** | Codex / GLM / Gemini (external APIs) | Multiple Claude instances |
| **Cost model** | Fixed-cost ($200+$15/mo) | Claude rate limit consumption |
| **Communication** | Claude -> External -> Claude | Members communicate directly |
| **Best for** | Daily tasks (95%) | Special parallel-coordination tasks (5%) |

### Decision Flow

```
Task received
    |
Does this need direct member-to-member communication?
+- No (95%) -> FUGUE (delegate to Codex/GLM)
+- Yes (5%) -> Further evaluation
    |
    Can Codex/GLM parallel execution substitute?
    +- Yes -> FUGUE (parallel-codex.js etc.)
    +- No  -> Agent Teams
```

### When to Use FUGUE (Default)

- Code review -> Codex/GLM
- Design decisions -> Codex architect
- Security analysis -> Codex security-analyst
- Summarization/translation -> GLM
- UI development -> Pencil MCP
- UI evaluation -> Gemini

**Why**: Stays within fixed costs. Does not consume Claude rate limits.

### When to Use Agent Teams (Limited)

| Scenario | Why Agent Teams Wins |
|----------|---------------------|
| Large codebase exploration | 5 members investigate different directories simultaneously, sharing discoveries |
| Competing hypothesis debugging | "Auth issue?" vs "DB connection?" investigated in parallel with real-time info sharing |
| Cross-layer implementation | Frontend / backend / tests written by different members, checking consistency directly |
| Codex + GLM both down | Fallback: Claude instances work together |

**Common thread**: Value comes from **direct member-to-member communication** during the task.

### Concrete Examples

**FUGUE is sufficient:**
> "Review this PR"
> -> Codex code-reviewer + security-analyst in parallel
> -> Integrate results and report

**Agent Teams is valuable:**
> "Unknown bug in the auto-registration system.
> Investigate auth flow, DB, webhooks, and external API simultaneously.
> Share findings in real-time to pinpoint the cause."
> -> 4 members investigate while exchanging information
> -> Member A: "Auth is clean" -> Member B: "Found invalid value in DB"
> -> Member C: "Let me check the webhook payload based on that"

### Rate Limit Impact

```
FUGUE:  Claude = routing only    (rate limit consumption: minimal)
Teams:  Claude x member count    (rate limit consumption: significant)
```

Agent Teams consumes a full context window per member. Apply the same caution as the "subagent prohibition" policy. Limit to 1-2 special tasks per week.

## Rate Limit Strategy

| Model | Target Usage | Role |
|-------|-------------|------|
| **Codex** | 120-150 calls/week | All code tasks + design + complex decisions |
| **GLM** | 120-150 calls/week | All non-code tasks + light review + classification |
| **Subagent (Haiku)** | <=5 calls/week | File exploration only |
| **Subagent (Sonnet)** | 0 calls/week | Prohibited (use Codex instead) |
| **Agent Teams** | 1-2 tasks/week | Complex parallel coordination only |
| **Claude Opus** | Minimal | Orchestration only |

## License

MIT

## Credits

Inspired by the FUGUE philosophy: Distributed autonomy x Unified convergence.
