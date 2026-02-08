# Codex Usage Rules

## Principle

**GPT Pro subscription active. Use aggressively without cost concerns.**

## Auto-Delegate (No Confirmation)

- When a third-party perspective is needed
- When specialized analysis is required
- When uncertain about a decision
- When research would take significant time
- On code changes (automatic review)
- On design decisions
- Implementation tasks

## Do Not Delegate

- Simple file reads
- Minor fixes (typo, 1-line changes)
- User conversation

## Invocation Methods

```bash
# CLI (recommended)
codex exec "[prompt]"

# MCP
mcp__codex__codex({ prompt: "..." })

# Script
node ~/.claude/skills/orchestra-delegator/scripts/delegate.js \
  -a [agent] -t "[task]" -f [file]
```

## Agent List

| Agent | Purpose | Auto-Trigger |
|-------|---------|-------------|
| architect | Design decisions | "design", "architecture" |
| scope-analyst | Requirements analysis | "requirements", "scope" |
| plan-reviewer | Plan verification | After Plans.md creation |
| code-reviewer | Code quality | On code changes |
| security-analyst | Security | Before commit |

## 7-Section Format

Prompts sent to Codex should follow this structure:

| Section | Content |
|---------|---------|
| TASK | Single clear goal |
| EXPECTED OUTCOME | Definition of success |
| CONTEXT | Code, diff, background |
| CONSTRAINTS | Technical constraints, existing patterns |
| MUST DO | Required actions |
| MUST NOT DO | Prohibited actions |
| OUTPUT FORMAT | JSON or other output format |

## Stateless

Each invocation is independent. Codex does not know previous conversations.
Include all necessary information in the prompt (Context-complete).
