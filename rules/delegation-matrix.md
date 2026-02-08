# Delegation Matrix (Single Source of Truth)

## Principle

**This file is the sole authoritative definition of delegation targets. All other files reference this.**

## Delegation Targets

### Cost Priority (Lightweight Tasks) -> GLM-4.7

| Trigger | Agent | Purpose | Parallel Limit |
|---------|-------|---------|----------------|
| Code changes, review | `code-reviewer` | Code quality (7-point scale) | 7 |
| Refactoring | `refactor-advisor` | Improvement suggestions | 7 |
| Math, algorithms | `math-reasoning` | Logic verification | 7 |
| General analysis | `general-reviewer` | Multi-purpose | 7 |

```bash
node ~/.claude/skills/orchestra-delegator/scripts/delegate-glm.js \
  -a [agent] -t "[task]" [-f file] [--thinking]
```

### Accuracy Priority (Critical Tasks) -> Codex

| Trigger | Agent | Purpose |
|---------|-------|---------|
| Design, architecture | `architect` | Design decisions |
| Requirements, scope | `scope-analyst` | Requirements analysis |
| Planning, estimates | `plan-reviewer` | Plan verification |
| Security, vulnerabilities | `security-analyst` | Security analysis |
| Critical code review | `code-reviewer` | High-accuracy review |

```bash
node ~/.claude/skills/orchestra-delegator/scripts/delegate.js \
  -a [agent] -t "[task]" -f [file]
```

### Specialty -> Gemini

| Trigger | Agent | Purpose |
|---------|-------|---------|
| UI, UX, design, colors | `ui-reviewer` | Design review |
| Images, screenshots | `image-analyst` | Image analysis |
| E2E screenshot verification | `agentic-vision` | Think-Act-Observe loop |

```bash
node ~/.claude/skills/orchestra-delegator/scripts/delegate-gemini.js \
  -a [agent] -t "[task]" -i [image]
```

### Realtime / X -> Grok (xAI)

| Trigger | Agent | Purpose |
|---------|-------|---------|
| X, Twitter, social media | `x-analyst` | Platform analysis |
| Trends, buzz | `trend-analyzer` | Trend analysis |
| Realtime news | `realtime-info` | Realtime information |

```bash
node ~/.claude/skills/orchestra-delegator/scripts/delegate-grok.js \
  -a [agent] -t "[task]" [-f file]
```

### Subagent (Prohibited by Default -- Rate Limit Mitigation 2026-02-08)

> Subagent (Haiku/Sonnet) consumes Claude API rate limit. Prohibited by default.
> Former Layer 3/4 tasks migrated to Codex/GLM.

| Former Layer | Former Target | **New Target** | Reason |
|-------------|--------------|----------------|--------|
| Layer 3 (lightweight) | Subagent (haiku) | **GLM general-reviewer** | Rate limit avoidance |
| Layer 4 (design) | Subagent Plan (sonnet) | **Codex architect** | Rate limit avoidance |
| Layer 4 (complex) | Subagent (sonnet) | **Codex scope-analyst** | Rate limit avoidance |
| File exploration | Subagent Explore (haiku) | **Subagent Explore (haiku)** | **Only exception** |

**Exceptions (Subagent allowed)**:
- `Task({ subagent_type: "Explore", model: "haiku" })` -- File exploration only
- **Orchestration review** -- Claude Opus participates directly (on user request)

## Selection Flowchart (2-Layer Orchestration v2)

```
Task received
    |
+- UI development/component/screen? --> Pencil MCP (required)
+- UI/UX evaluation only? -----------> Gemini ui-reviewer (strict)
+- Code-centric?
|   +- Code fix/refactor ------------> Codex
|   +- Test creation/CI investigation -> Codex code-reviewer
|   +- Config/infrastructure --------> Codex architect
|   +- Architecture design ----------> Codex architect (former Layer4)
|   +- High-risk decision -----------> Codex scope-analyst (former Layer4)
+- Non-code (summary/translation/classification)?
|   +- Summary, translation, tl;dr --> GLM general-reviewer (former Layer3)
|   +- Tags, classification --------> GLM general-reviewer (former Layer3)
|   +- Math/calculation ------------> GLM math-reasoning
+- File exploration? ----------------> Subagent Explore (haiku) [only exception]
+- X/Twitter/trends/realtime? -------> Grok
+- Diagrams/flowcharts? ------------> Excalidraw
+- Browser automation? -------------> Manus browser
+- Orchestration review? -----------> Claude Opus direct participation (required)
+- Can't decide? ------------------> Codex architect (former Layer4)
```

**2-Layer Orchestration Principles (v2)**:
- **Layer 1 Codex**: All code + design + security + complex decisions (maximize $200/mo)
- **Layer 2 GLM**: All non-code + light review + summary + classification (maximize $15/mo)
- **Subagent prohibited**: Haiku/Sonnet consume Claude rate limit. Explore only exception.
- **Opus = Orchestrator only**: Routing, integration, reporting. No direct task execution.

## Cost Guidelines (2-Layer v2)

| Target | Layer | Cost | Criteria | Target Usage |
|--------|-------|------|----------|-------------|
| **Codex** | **Layer 1** | **$200/mo (fixed)** | **All code + design + complex** | **120-150/week** |
| **GLM-4.7** | **Layer 2** | **$15/mo (fixed)** | **All non-code + review + classify** | **120-150/week** |
| ~~Subagent(haiku)~~ | ~~Layer 3~~ | ~~Claude MAX~~ | **Prohibited** (Explore only) | **<=5/week** |
| ~~Subagent(sonnet)~~ | ~~Layer 4~~ | ~~Claude MAX~~ | **Prohibited** (migrated to Codex) | **0/week** |
| Claude Opus | Orchestrator | Claude MAX | **Routing/integration/reporting only** | **Minimal** |
| Gemini | Special | Pay-as-you-go | **UI/UX evaluation only (strict)** | **10-15/week** |

## Auto-Delegation Triggers

These execute automatically without confirmation:

| Event | Target | Condition |
|-------|--------|-----------|
| After code edit | GLM code-reviewer | 10+ line changes |
| Before commit | Codex security-analyst | Always |
| Design decision | Codex architect | Always |
| After Plans.md creation | Codex plan-reviewer | Always |
| After design completion | Gemini ui-reviewer | Critical UI only (optional) |
