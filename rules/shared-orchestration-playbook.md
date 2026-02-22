# Shared Orchestration Playbook (Codex / Claude)

Purpose: provider-agnostic execution baseline inspired by high-signal CLAUDE.md practices.
This playbook is designed to work the same way when the main orchestrator is `codex` or `claude`.

## 1) Plan Node Default

- For non-trivial tasks (3+ steps, architecture changes, migrations), enter plan mode first.
- If a cycle finds a blocker, stop and re-plan instead of pushing forward.
- Use the same planning standard for verification as for implementation.

## 2) Subagent Strategy

- Use subagents for scoped exploration and parallel analysis.
- Keep one clear task per subagent.
- Keep the main context focused on integration decisions.
- In `claude-light` profile, reduce optional subagent fan-out first.

## 3) Mandatory Preflight Loop (Before Implementation)

Repeat in order:
1. Plan
2. Parallel Simulation
3. Critical Review
4. Problem Fix
5. Replan

Defaults:
- `codex-full`: 3 cycles (up to 5 for high-risk changes)
- `claude-light`: 1-3 cycles based on rate-limit pressure

Hard gates:
- Parallel Simulation and Critical Review cannot be skipped.

## 4) Implementation Collaboration Loop

For each round:
1. Implementer Proposal
2. Critic Challenge
3. Integrator Decision
4. Applied Change
5. Verification

Apply only integrator-approved changes.

## 5) Task Management Contract

- Track executable checklist items in `.fugue/pre-implement/issue-<N>-todo.md`.
- Include a short review/result section in the same file.
- Mark progress during execution; do not postpone status updates to the end.

## 6) Self-Improvement Loop

- After user correction or postmortem finding, append a durable rule to `.fugue/pre-implement/lessons.md`.
- Rule format:
  - Mistake pattern
  - Preventive rule
  - Trigger signal
- Review relevant lessons at session start when available.

## 7) Verification Before Done

- Never mark done without evidence.
- Validate behavior with tests/logs/diffs appropriate to the change.
- Ask: "Would this pass staff-level review?"

## 8) Elegance Gate (Balanced)

- For non-trivial changes, challenge hacky fixes and prefer cleaner alternatives.
- Skip over-engineering for simple, obvious fixes.
- Keep change surface minimal.

## 9) Autonomous Bug Fixing

- For bug reports: diagnose from logs/tests first, then fix directly.
- Minimize user context switching.
- If CI fails, triage and remediate without waiting for detailed hand-holding.
