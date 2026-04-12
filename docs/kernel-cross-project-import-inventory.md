# Kernel Cross-Project Import Inventory

## Goal

Apply the same `import as-is / transform / reject` logic across project-local `CLAUDE.md`, `AGENTS.md`, and `SKILL.md` assets under `/Users/masayuki/Dev`.

This inventory is for `Kernel` migration planning, not for blindly importing every file into Codex App.

## Classification Rules

### Import As-Is

Use as-is when the asset is:

- a thin adapter
- a concise load-order guide
- a stable project-specific command/index document
- a specialist skill with low governance risk

### Import But Transform

Use after translation when the asset is:

- operationally valuable but too long or too role-specific
- a good project context file with stale or mixed control-plane assumptions
- a harness/delegation asset whose authority model must change

### Reject From Kernel Core

Reject from Kernel governing logic when the asset:

- assumes Claude sovereignty
- encodes legacy provider hierarchy as architecture
- duplicates policy in multiple places
- is stale enough to lower precision rather than improve it

## Inventory

| Project | Files reviewed | Pattern | Kernel class | Notes |
|---|---|---|---|---|
| `fugue-orchestrator` | `AGENTS.md`, `CLAUDE.md`, `CODEX.md` | thin adapter + deep policy | import as-is + Kernel-native | already the canonical Kernel design host |
| `Content_Analyzer` | `AGENTS.md`, `.claude/CLAUDE.md` | mixed/stale local context | transform | `AGENTS.md` and `CLAUDE.md` appear to describe different backend shapes |
| `Miyabi` | `CLAUDE.md` | thin pointer adapter | import as-is | good model for context-budget discipline |
| `cmux/repo` | `AGENTS.md`, `CLAUDE.md` | duplicate operational guide | transform | project commands are valuable; duplication should be deduped |
| `cursorvers_line_free_dev` | `CLAUDE.md` | operational project context | transform | valuable contract file, but test counts/status text can drift |
| `fugue-orchestrator-public` | `CLAUDE.md` | legacy Claude-led doctrine | reject from Kernel core | useful only as historical comparison |
| `novim` | `CLAUDE.md` | stable project documentation | import as-is | compact and repo-specific |
| `skills` | `CLAUDE.md` | repository policy for skills | import as-is | useful for skill repo contribution behavior |
| `spec-driven-codex` | `AGENTS.md`, `CLAUDE.md` | clean repo guidelines + project context | import as-is | strong example of low-noise repo guidance |
| global Claude assets | `~/.claude/CLAUDE.md`, `~/.claude/AGENTS.md`, representative skills | thin adapter + deep skill assets | import as-is / transform by type | good source of reusable operating knowledge |

## Per-Project Findings

### fugue-orchestrator

- This is the main Kernel design host.
- `CLAUDE.md` is already a thin adapter.
- `CODEX.md` has been added to make Codex App import explicit.
- Action:
  - keep as the Kernel reference implementation for import doctrine

### Content_Analyzer

- `AGENTS.md` is a Codex-focused repo guideline and is structurally useful.
- `.claude/CLAUDE.md` is rich but appears to conflict with `AGENTS.md` on architecture details.
- Example:
  - `AGENTS.md` describes Node/Express/tRPC/Drizzle
  - `.claude/CLAUDE.md` describes Supabase Edge Functions/Deno
- Kernel implication:
  - import only after reconciling the architecture source of truth
- Action:
  - treat `AGENTS.md` as the more governance-friendly base
  - rewrite local `CLAUDE.md` into a thin pointer adapter

### Miyabi

- `CLAUDE.md` is exactly the style Kernel wants:
  - overview
  - minimal commands
  - critical rules
  - pointers to deeper docs
- Kernel implication:
  - strong candidate for direct Codex App import
- Action:
  - use as a template pattern for other repos

### cmux/repo

- `AGENTS.md` and `CLAUDE.md` are effectively duplicated.
- The content is still valuable:
  - setup commands
  - build/reload policy
  - UI test constraints
  - threading/focus policy
- Kernel implication:
  - project knowledge is useful
  - duplicated copies increase drift risk
- Action:
  - keep one canonical project guide
  - make the other file a thin adapter pointer

### cursorvers_line_free_dev

- `CLAUDE.md` captures the business system well.
- It is useful for import because it explains LINE, Stripe, Discord, Manus, and Supabase surfaces.
- However, status blocks are time-sensitive and already drift-prone.
- Example:
  - file says `280件 pass (545 steps)`
  - current verified result is `506 passed`, `0 failed`, `2 ignored`
- Kernel implication:
  - importable after trimming volatile status text
- Action:
  - rewrite as:
    - architecture
    - commands
    - critical contracts
    - pointers
  - remove snapshot metrics from the adapter

### fugue-orchestrator-public

- This file is historically useful but architecturally unsafe for Kernel.
- It explicitly encodes:
  - `Claude = Orchestrator`
  - dual-tier delegation logic
  - subagent restrictions derived from Claude limits
- Kernel implication:
  - do not import into Kernel core
- Action:
  - keep only as historical lineage material

### novim

- Good compact project documentation.
- Mostly project-specific behavior and testing checklist.
- Kernel implication:
  - safe to import directly as repo context
- Action:
  - import as-is

### skills

- Good repo-level contribution guidance for skill development.
- Kernel implication:
  - useful for any repo that will produce Codex-importable skills
- Action:
  - import as-is where skill authoring is relevant

### spec-driven-codex

- `AGENTS.md` is a strong, low-noise repository guideline.
- `CLAUDE.md` is project-specific and focused on commands/architecture/testing.
- Kernel implication:
  - high-quality import candidate
- Action:
  - import as-is

## Skills Direction

### Import As-Is

- project-local `SKILL.md` files that are specialist capability docs
- `skills/CLAUDE.md` repo guidance for skill authoring
- global skill families that are capability-first and not governance-first

### Import But Transform

- `claude-code-harness`
- `orchestra-delegator`
- any skill that assumes Claude is the authority and Codex is only a delegate

### Reject From Kernel Core

- skills whose main value is preserving Claude sovereignty
- skills that duplicate long orchestration policy instead of capabilities

## Precision Impact Summary

Using project-local and global Claude-era assets in Codex App should improve precision if:

1. adapters are thin
2. stale status blocks are removed
3. duplicated governance files are deduped
4. legacy Claude-led doctrine is excluded
5. capability skills are imported separately from authority rules

If these conditions are not met, import can reduce precision by loading conflicting or stale instructions.

## Recommended Next Actions

1. Rewrite drift-prone project `CLAUDE.md` files into thin adapters:
   - `Content_Analyzer`
   - `cursorvers_line_free_dev`
   - `cmux/repo`
2. Keep pointer-style adapters as the standard:
   - `Miyabi` should be treated as a reference pattern
3. Keep legacy Claude-led doctrine out of Kernel:
   - `fugue-orchestrator-public`
4. When importing into Codex App, separate:
   - repo adapters
   - governance docs
   - capability skills
