# Quick Reference — Delegation & Execution Scripts

> On-demand reference. Extracted from CLAUDE.md to reduce always-loaded context.

## Delegation Scripts

```bash
# Codex (primary execution engine)
node ~/.claude/skills/orchestra-delegator/scripts/delegate.js \
  -a [architect|code-reviewer|security-analyst] -t "[task]"

# Cursor CLI (supplementary, FUGUE_EXECUTION_PROVIDER=cursor)
agent --model auto -p --workspace /path "[task prompt]"

# GLM-5 (cost priority)
node ~/.claude/skills/orchestra-delegator/scripts/delegate-glm.js \
  -a [code-reviewer] -t "[task]"

# Gemini (UI/UX)
node ~/.claude/skills/orchestra-delegator/scripts/delegate-gemini.js \
  -a [ui-reviewer] -t "[task]" -i [image]
```

## Lane Bridge (v3.0)

```bash
# Unified dispatch with failover
node ~/.claude/skills/orchestra-delegator/scripts/fugue-lane-bridge.mjs \
  --lane codex:architect --task "[task]" --project /path

# Pre-validate matrix (exit 2 on diversity violation)
node ~/.claude/skills/orchestra-delegator/scripts/fugue-lane-bridge.mjs \
  --validate matrix.json

# Operations dashboard
node ~/.claude/skills/orchestra-delegator/scripts/fugue-lane-bridge.mjs \
  --dashboard --days 7
```

## Structured Execution (v3.0)

```bash
# Autonomous 9-step execution
node ~/.claude/skills/orchestra-delegator/scripts/fugue-execute.mjs \
  --task "[task]" --project /path --tier auto

# Dry-run (no provider calls, for testing)
node ~/.claude/skills/orchestra-delegator/scripts/fugue-execute.mjs \
  --dry-run --task "fix typo" --tier 0
```

## System Architecture

```
User
    | instruction
Claude (Orchestrator)
    | planning & routing
+-------------------------------------+
| Execution Tier                      |
| +-> Codex (design, code, security)  |
| +-> GLM-5 (lightweight review)      |
| +-> Gemini (UI/UX, image analysis)  |
| +-> Pencil MCP (.pen UI dev)        |
| +-> MCP Tools (Stripe, Supabase...) |
+-------------------------------------+
    | artifacts
+-------------------------------------+
| Evaluation Tier [auto]              |
| +-> Gemini (UI/UX evaluation)       |
| +-> GLM (code quality)              |
| +-> Codex (security audit)          |
+-------------------------------------+
    | feedback
Claude (integrate & report)
```
