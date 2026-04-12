# Delegation Flow Details

**Delegation targets are defined in `delegation-matrix.md`. This file defines the process of *how* to delegate.**

## Principles

1. **Delegate immediately**: Classify and delegate upon task receipt (no confirmation)
2. **Parallel first**: Independent tasks must always run in parallel
3. **Via evaluation tier**: Artifacts pass through evaluation before reporting
4. **Integrate results**: Combine delegation results and report to user

## Dual-Tier Architecture

```
Claude (Orchestrator)
    | planning & routing
+----------------------------------+
| Execution Tier                   |
| Codex / GLM / Pencil / etc.     |
+----------------------------------+
    | artifacts
+----------------------------------+
| Evaluation Tier                  |
| Gemini UI/UX / GLM Review       |
+----------------------------------+
    | feedback
Claude (integrate & report)
```

### Evaluation Tier Roles

| Evaluator | Responsibility | Criteria |
|-----------|---------------|----------|
| Gemini ui-reviewer | UI/UX, design | Visual consistency, UX quality |
| GLM code-reviewer | Code quality | Readability, maintainability, performance |
| Codex security-analyst | Security | Vulnerabilities, auth, data protection |

## Parallel Execution Rules

### Must Run in Parallel

- Independent research tasks
- Analysis of different files
- Pre-commit checks (code-reviewer + security-analyst)

### Must Run Sequentially

- Tasks with dependencies (A's output is B's input)
- Changes to the same file

## 7-Section Format (For Codex Prompts)

| Section | Content |
|---------|---------|
| TASK | Single clear goal |
| EXPECTED OUTCOME | Definition of success |
| CONTEXT | Code, diff, background |
| CONSTRAINTS | Technical constraints, existing patterns |
| MUST DO | Required actions |
| MUST NOT DO | Prohibited actions |
| OUTPUT FORMAT | JSON or other output format |

**Note**: Codex is stateless. Include all necessary information in each prompt.

## Fallback

When external services (Codex/GLM/Gemini) are unavailable:

1. **Timeout**: 30 seconds, then next priority
2. **Solo judgment**: Security > Accuracy > Performance > Readability
3. **Record**: Always log the reasoning
4. **Follow-up**: Request review after service recovery
