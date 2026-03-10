# Performance Rules

## Principle

**Select models by task complexity. Use context efficiently.**

## Model Selection Guide

| Model | Use Case | Cost | Characteristics |
|-------|----------|------|----------------|
| **GLM-4.7** | Code review, light analysis, math | Lowest ($15/mo) | Stable up to 7 parallel |
| **Haiku** | Pair programming, light agents | Low | 90% of Sonnet, 3x cost reduction |
| **Sonnet** | Main development, complex coding | Medium | Standard model |
| **Opus** | Deep reasoning, architecture design | High | Accuracy priority |
| **Codex** | Design decisions, security analysis | High (GPT Pro) | Specialized tasks |

## Context Window Strategy

```
200k tokens
+-- 80% (160k) - Main work area
+-- 20% (40k)  - Reserved (simple tasks)
```

### Recommendations

- Keep MCP count under 10 per project
- Warning at 20+ MCPs
- Disable unused MCPs during large refactors

## Code Optimization

| Issue | Solution |
|-------|---------|
| N+1 queries | Batch fetch, JOIN |
| Unnecessary re-renders | useMemo, useCallback |
| Large datasets | Pagination, virtualization |
| Heavy computation | Web Workers, caching |

## Parallel Execution

```javascript
// Independent tasks: always parallel
Promise.all([
  task1(),
  task2(),
  task3()
])

// GLM parallel limit: 7
// 8+ parallel = 429 errors
```
