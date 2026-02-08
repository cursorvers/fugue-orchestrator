# Auto-Execution Rules

## Principle

**The following execute automatically without confirmation.**

## Triggers -> Auto-Execution (2-Layer Orchestration v2)

> **Rate Limit Mitigation**: Agent Teams causes low Claude rate limit thresholds.
> Subagent (Haiku/Sonnet) prohibited by default. Migrated to Codex/GLM.
> **Opus = Orchestrator only** (routing, integration, reporting).

### Layer 1: Codex (All Code + Design + Security + Complex Decisions)

| Trigger | Action | Target | Condition |
|---------|--------|--------|-----------|
| Code, bug fix, refactor | Code modification | Codex | Immediate |
| Test, patch, diff | Test creation/update | Codex code-reviewer | Immediate |
| CI, build | CI investigation/fix | Codex architect | Immediate |
| TypeScript, Python, SQL | Language-specific impl | Codex | Immediate |
| Pre-commit | Security check | Codex security-analyst | On `git add` |
| Design, architecture | System design | Codex architect | Immediate (former Layer4) |
| Tradeoff, strategy | Complex decision | Codex scope-analyst | Immediate (former Layer4) |
| Risk, security, performance | High-risk evaluation | Codex security-analyst | Immediate (former Layer4) |
| Ambiguous requirements | Scope analysis | Codex scope-analyst | Immediate (former Layer4) |
| After Plans.md creation | Plan verification | Codex plan-reviewer | On file save (former Layer4) |

### Layer 2: GLM (All Non-Code + Light Review + Summary + Classification)

| Trigger | Action | Target | Condition |
|---------|--------|--------|-----------|
| Summary, translation | Short summary/translation | GLM general-reviewer | Immediate |
| tl;dr, one-liner | Ultra-short summary | GLM general-reviewer | Immediate (former Layer3) |
| Tags, classification | Categorization | GLM general-reviewer | Immediate (former Layer3) |
| FAQ, templates | Document formatting | GLM | Immediate |
| Math, algorithms | Logic verification | GLM math-reasoning | Immediate |
| Code changes (10+ lines) | Light review | GLM code-reviewer | On change completion |
| Code artifact complete | Quality check | GLM code-reviewer | On implementation completion |

### Exception: Subagent Explore (File Exploration Only)

| Trigger | Action | Target | Condition |
|---------|--------|--------|-----------|
| Find files, search | File exploration | Subagent Explore (haiku) | Only when Codex/GLM cannot |

### Opus Direct Participation: Orchestration Review

| Trigger | Action | Target | Condition |
|---------|--------|--------|-----------|
| Orchestration review | Overall optimization | **Claude Opus direct** | On user request (required) |

### ~~Layer 3: Haiku (Abolished)~~
### ~~Layer 4: Sonnet (Abolished)~~

> Former Layer 3/4 **abolished** due to Claude rate limit consumption. Migrated to Codex/GLM.

## Strategy (2-Layer v2)

**Goal**: Claude rate limit avoidance + fixed-cost maximization + Opus orchestrator focus

### Auto-Adjustment Rules

```
Weekly monitoring:
+- Subagent usage > 5/week -> Warning (consider migrating to Codex/GLM)
+- Codex usage < 120/week -> Move boundary tasks to Layer 1 (underutilizing fixed cost)
+- GLM usage < 120/week -> Move summary/classification to Layer 2
+- Same task fails 2x -> Escalate to different Codex agent
```

### Expected Impact

- Codex: 80-100/week -> **120-150/week** (absorbing former Layer4)
- GLM: 100/week -> **120-150/week** (absorbing former Layer3)
- Claude Subagent: 30-45/week -> **<=5/week** (Explore only)
- Claude Opus: Orchestrator only (minimal rate limit consumption)

## Evaluation Tier

**After execution, artifacts automatically pass through evaluation.**

```
Execution Tier (Codex/GLM/Pencil/etc.)
    | artifact complete
Evaluation Tier (auto-trigger)
+-- UI/UX artifact -> Gemini ui-reviewer
+-- Code artifact -> GLM code-reviewer
+-- Security-related -> Codex security-analyst
    |
Claude (feedback integration)
    |
Report to user
```

### Evaluation Skip Conditions

- User explicitly specifies `--skip-eval`
- Minor changes (<5 lines, typo fixes)
- Research/exploration tasks (no artifacts)

## Single-Path Router v2

### Task Classification

| Task Type | Condition | Target | Reason |
|-----------|-----------|--------|--------|
| All code | Code-centric (any complexity) | **Codex** | Maximize fixed cost |
| Design/architecture | Design decisions, complex | **Codex architect** | Former Layer4 migrated |
| All non-code | Summary, translation, classification | **GLM** | Maximize fixed cost |
| File exploration | Codebase search | **Subagent Explore (haiku)** | Only exception |
| Orchestration review | Overall optimization | **Claude Opus direct** | On user request |

### Execution Flow

```
Task received
    |
Opus Orchestrator (routing only)
    |
+- Code-centric? ----------> Codex (all complexity levels)
+- Non-code? --------------> GLM (all lightweight tasks)
+- File exploration? -------> Subagent Explore (haiku) [only exception]
+- Orchestration review? ---> Claude Opus direct participation
+- Can't decide? ----------> Codex architect
    |
Integrate results -> Report to user
```

## Fallback Rules (v2 -- Subagent Minimized)

| Failed Service | Fallback | Condition |
|---------------|----------|-----------|
| **Codex** | **GLM** (non-code) / **Subagent Explore** (search only) | Timeout 30s or 3 retries |
| **GLM** | **Codex** (general analysis) | Timeout 30s or 3 retries |
| **Gemini** | GLM general-reviewer | Timeout 30s (non-image only) |
| **Grok** | WebSearch + GLM | X-related waits, others substitute |
| **Codex + GLM both down** | **Subagent (sonnet)** (emergency only) | Both services down simultaneously |

## Parallel Execution

**Independent tasks must always run in parallel.**

```bash
# Codex parallel execution (recommended: parallel-codex.js)
node ~/.claude/skills/orchestra-delegator/scripts/parallel-codex.js \
  --agents "architect,scope-analyst" -t "<task>"

# GLM parallel execution (max 7 concurrent)
node delegate-glm.js -a code-reviewer -t "TaskA" &
node delegate-glm.js -a code-reviewer -t "TaskB" &
wait
```
