# Kernel Codex Import Strategy

## Goal

Use Codex App support for importing `CLAUDE.md` and Claude skills to improve `Kernel` precision without reintroducing a Claude-led control plane.

The purpose of import is:

- preserve operational knowledge
- preserve specialist workflow triggers
- improve consistency of planning, delegation, and verification
- reduce migration loss from the existing Claude-era operating model

The purpose is **not**:

- restoring Claude as the sovereign orchestrator
- importing rate-limit-driven architecture constraints into Kernel core
- duplicating long policy text into multiple adapters

Clarification:

- future `Claude main` is not forbidden
- it is simply not allowed to return as an implicit core assumption
- it must re-enter only through an explicit Kernel sovereign adapter

## Source Files Reviewed

### Local repo

- `/Users/masayuki/Dev/fugue-orchestrator/CLAUDE.md`

### Global Claude adapter/policy

- `/Users/masayuki/.claude/CLAUDE.md`
- `/Users/masayuki/.claude/AGENTS.md`

### Representative skills

- `/Users/masayuki/.claude/skills/claude-code-harness/SKILL.md`
- `/Users/masayuki/.claude/skills/orchestra-delegator/SKILL.md`

## Import Classification

### 1. Import As-Is

These items are already compatible with Kernel and should be imported with minimal or no translation.

1. `Thin adapter pattern`
   - Local and global `CLAUDE.md` are intentionally small.
   - They define read order and keep policy in `AGENTS.md`.

2. `Read order / context budget`
   - Load local `AGENTS.md` first.
   - Load local adapter second.
   - Fall back to global policy only when needed.
   - Load deep docs only on demand.

3. `Auditable provider behavior`
   - Provider logic and fallback decisions should remain explicit and reviewable.

4. `Adapter contract`
   - Adapter files should stay short and role-specific.

5. `Design skill discipline`
   - Global design principle policy is reusable:
     - authority references
     - AI-checkable rules
     - mandatory review chain

### 2. Import But Transform For Kernel

These are valuable, but they must be rewritten around Codex ownership.

1. `claude-code-harness`
   - Keep:
     - structured planning
     - work/review/verify phases
     - explicit hooks/guards mindset
   - Transform:
     - from `Claude harness + Codex delegation`
     - into `Codex Harness Core + optional Claude executor lanes`

2. `orchestra-delegator`
   - Keep:
     - explicit role table
     - low-friction auto-delegation doctrine
     - context-complete task packets
     - 7-section delegation format
   - Transform:
     - Codex becomes the default delegator and state owner
     - GLM/Gemini/Claude become specialist lanes under Kernel

3. `auto execution heuristics`
   - Keep:
     - delegate automatically when ambiguity or specialist judgment is needed
   - Transform:
     - final gate must remain Kernel council controlled

4. `review templates`
   - Keep:
     - scope analysis
     - architect review
     - plan review
     - code review schemas
   - Transform:
     - bind them to `small / medium / large / critical` Kernel topology classes

### 3. Reject From Kernel Core

These should not be imported into Kernel as governing logic.

1. `Claude may act as orchestrator depending on project policy`
   - Do not import this as a default Kernel core assumption.
   - If needed in the future, it belongs in `claude-sovereign-compat`, not in generic Kernel doctrine.

2. `Claude rate-limit architecture constraints as a global law`
   - These belong only inside Claude-specific lanes.

3. `Subagent prohibition derived from Claude limits`
   - Kernel should prefer Codex multi-agent as the normal fast path.

4. `Legacy override paths that imply Claude sovereignty`
   - Examples:
     - `--force-claude`
     - `orchestrator-force:claude`
   - These may remain only for legacy Claude-side compatibility.

## Kernel Import Set

The recommended first import set for Codex App is:

1. Local `CLAUDE.md`
   - for repo-specific operational anchors

2. Global `CLAUDE.md`
   - for thin adapter conventions

3. Global `AGENTS.md`
   - for context budget and adapter discipline

4. Skill families to import conceptually
   - `claude-code-harness`
   - `orchestra-delegator`
   - `slide`
   - `generate-video`
   - `design-ref`
   - `openclaw-github`
   - `openclaw-model-usage`
   - `openclaw-tmux`

Note:

- Importing these into Codex App does not mean preserving their original Claude sovereignty assumptions.
- Kernel should treat them as capability assets, not governance assets.

## Expected Precision Gains

Import should improve precision in the following ways:

1. `Better task packet quality`
   - The 7-section delegation format reduces ambiguity in multi-agent fan-out.

2. `Better specialist routing`
   - Existing skill triggers help Codex choose when to invoke slide/video/design/adapter workflows.

3. `Better review consistency`
   - Harness-era review schemas reduce variance in plan and code critique.

4. `Better migration continuity`
   - Existing operator knowledge moves into Codex App instead of living only in Claude-side tooling.

5. `Lower context waste`
   - Thin adapters and on-demand loading fit the Kernel objective of keeping the orchestrator sharp.

## Codex Harness Core Translation

The imported Claude harness concepts should be rewritten as the following Kernel modules:

| Imported concept | Kernel equivalent |
|---|---|
| Claude harness | Codex Harness Core |
| Codex delegation | Codex multi-agent fan-out |
| GLM side review | baseline council lane |
| Claude sidecar | Claude executor / adapter lane |
| harness review | Kernel verification fabric |
| permission hooks | Kernel risk gate |

## Operational Rule

When Codex App imports Claude-era assets:

- `knowledge` is preserved
- `authority` is not

This is the core translation rule for Kernel.

## Ready Follow-Up

The next implementation-facing step is:

1. Create a `Kernel CODEX.md` adapter that references:
   - `AGENTS.md`
   - `requirements-gpt54-codex-kernel.md`
   - `kernel-preimplementation-readiness.md`
   - `kernel-codex-import-strategy.md`
2. Translate the useful portions of `claude-code-harness` into a `Codex Harness Core` skill or rule pack.
3. Keep the current cross-repo verification harness as mandatory preflight during the migration.
