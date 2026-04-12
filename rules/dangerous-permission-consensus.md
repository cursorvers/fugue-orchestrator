# Dangerous Operation Consensus Rules

## Overview

Dangerous operations use a **2-level** judgment system:

1. **System-wide destructive operations** -> **User authentication required**
2. **Other dangerous operations** -> **3-party consensus** (no user confirmation needed)

## Consensus Members

```
+------------------------------------------+
| 3-Party Consensus = Claude + Codex + (GLM|Gemini) |
+------------------------------------------+
| [Fixed Members]                          |
| 1. Claude (Orchestrator) - Primary judge |
| 2. Codex security-analyst - Security     |
|                                          |
| [Variable Member (one of)]               |
| 3. GLM general-reviewer (default)        |
|    or                                    |
|    Gemini ui-reviewer (UI/UX-related)    |
+------------------------------------------+
```

### Third-Party Selection

| Operation Type | Third Party | Reason |
|---------------|-------------|--------|
| UI/UX/design-related | **Gemini** | Visual judgment needed |
| Everything else (default) | **GLM** | Cost efficiency |

## Level 1: User Authentication Required (System-Destructive)

The following **always require user confirmation**:

| Category | Trigger |
|----------|---------|
| Production | Production DB operations, production server changes |
| Git (irreversible) | Force push to `main`/`master` |
| System | OS config changes, system file deletion |
| Full deletion | Entire project deletion, `rm -rf /` |
| Credential leak | Sending credentials to external services |

## Level 2: Consensus (No User Confirmation)

The following are **judged by 3-party consensus**:

| Category | Trigger |
|----------|---------|
| Bash | Requires `dangerouslyDisableSandbox: true` |
| Git | `--force`, `--hard`, `reset`, `rebase -i` (non-main) |
| System | `sudo`, `chmod 777`, writes to `/etc/` |
| Delete | `rm -rf`, mass file deletion (10+) |
| Network | Sending secrets externally, unknown endpoints |
| Credentials | `.env`, `credentials`, `secrets` operations |

## Decision Flow

```
Dangerous operation detected
    |
Level classification
+- Level 1 (system-destructive) -> Ask user for confirmation
|     |
|   User approves -> Execute
|   User rejects -> Abort
|
+- Level 2 (other dangerous) -> Consensus
      |
  Parallel delegation to 3 parties
  +- 1. Claude (self-assessment): risk 1-5, alternatives
  +- 2. Codex security-analyst: security analysis, approve/reject
  +- 3. Third party (GLM or Gemini): validity check
      |
  Vote tally
  +- 3 approve -> Execute immediately
  +- 2 approve -> Execute with conditions (log recorded)
  +- 1 approve -> Reject (present alternatives)
  +- 0 approve -> Full reject
```

## Approval Criteria

- Operation purpose is clear
- Impact scope is limited
- Rollback is possible
- More efficient than alternatives

## Rejection Criteria

- Production environment impact
- Irreversible changes
- Credential leak risk
- Safer alternative exists

## Emergency Override

Claude may execute alone only when:
- Codex/GLM/Gemini don't respond within 30 seconds
- Obvious bug fix (impact within 1 file)
- User explicitly says "urgent"

Override must be logged and reviewed later.

## Absolute Prohibitions (Rejected Even by Consensus)

- Direct production DB deletion
- Force push to `main`/`master`
- Storing credentials in plaintext
- Sending credentials to external services
