# Shared Orchestration Playbook (Codex / Claude)

Purpose: provider-agnostic execution baseline inspired by high-signal CLAUDE.md practices.
This playbook is designed to work the same way when the main orchestrator is `codex` or `claude`.

## Policy Boundaries (MUST / SHOULD / MAY)

- MUST:
  - Preflight loop gates (Plan -> Parallel Simulation -> Critical Review -> Problem Fix -> Replan).
  - Implementation dialogue gates (Implementer -> Critic -> Integrator -> Applied Change -> Verification).
  - Verification evidence before completion.
- SHOULD:
  - Append lessons when correction/postmortem signals are present.
  - Keep task tracking artifacts current during execution.
- MAY:
  - Use additional subagent fan-out when uncertainty remains after first-pass analysis.
  - Run extra elegance comparisons for non-trivial changes when time permits.

## 1) Plan Node Default

- For non-trivial tasks (3+ steps, architecture changes, migrations), enter plan mode first.
- If a cycle finds a blocker, stop and re-plan instead of pushing forward.
- Use the same planning standard for verification as for implementation.

## 1.1) Research Artifact First

- Before planning, produce a deep-read research artifact.
- Recommended path: `.fugue/pre-implement/issue-<N>-research.md`.
- The artifact should capture:
  - existing flows and coupling points
  - hidden constraints and failure modes
  - likely bug/risk hotspots
- Do not start implementation before research has been reviewed.

## 1.2) Plan Artifact and Annotation Cycle

- Planning artifact path: `.fugue/pre-implement/issue-<N>-plan.md`.
- The plan file is a review surface, not just a chat summary.
- Run an annotation cycle 1-6 times as needed:
  1. Generate/update plan artifact
  2. Add inline review notes/constraints
  3. Return to agent: "address all notes, update plan, don't implement yet"
- Implementation starts only after explicit approval of the plan artifact.

## 2) Subagent Strategy

- Use subagents for scoped exploration and parallel analysis.
- Keep one clear task per subagent.
- Keep the main context focused on integration decisions.
- In `claude-light` profile, reduce optional subagent fan-out first.
- Do not fan out by default on low-risk tasks.

## 2.1) Context Budget (Staged Expansion)

- `low` risk: start with 6 sources, expand only when blocked (max 12).
- `medium` risk: start with 8 sources, expand only when blocked (max 16).
- `high` risk: start with 10 sources, expand only when blocked (max 20).
- Over-compression guard is always-on: if budget falls below floor/span policy, auto-correct before execution.
- Always summarize exploration output into short integration notes before continuing.

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
- Use plan artifact as the single source of progress:
  - mark completed items directly in plan/todo artifacts during execution
  - avoid drifting status reports that are not reflected in artifacts

## 6) Self-Improvement Loop

- After user correction or postmortem finding, append a durable rule to `.fugue/pre-implement/lessons.md`.
- Rule format:
  - Mistake pattern
  - Preventive rule
  - Trigger signal
- Review relevant lessons at session start when available.

## 6.1) Correction Signals

- Treat these as correction/postmortem signals:
  - Issue labels: `user-corrected`, `postmortem`, `regression`, `incident`
  - Text signals: `user correction`, `postmortem`, `lessons learned`, `再発防止`, `根本原因`

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
