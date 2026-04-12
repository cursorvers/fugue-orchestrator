# Source: AGENTS.md §10 — Shared Workflow Playbook
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 10. Shared Workflow Playbook (Codex/Claude)

- Provider-agnostic playbook source:
  - `rules/shared-orchestration-playbook.md`
- The playbook applies to both orchestrator profiles:
  - `codex-full`
  - `claude-light`
- Control-plane enforcement in implement mode must keep:
  - Preflight refinement loop gates
  - Implementation collaboration dialogue gates
  - Research artifact (`.fugue/pre-implement/issue-<N>-research.md`)
  - Plan artifact (`.fugue/pre-implement/issue-<N>-plan.md`)
  - Critic artifact (`.fugue/pre-implement/issue-<N>-critic.md`)
  - Task tracking artifact (`.fugue/pre-implement/issue-<N>-todo.md`)
  - Lessons artifact (`.fugue/pre-implement/lessons.md`)
  - MUST/SHOULD/MAY boundaries with staged context budget (see `rules/shared-orchestration-playbook.md`)
  - Always-on over-compression guard via `FUGUE_CONTEXT_BUDGET_MIN_INITIAL`, `FUGUE_CONTEXT_BUDGET_MIN_MAX`, `FUGUE_CONTEXT_BUDGET_MIN_SPAN`
  - Parallel preflight nodes for research/plan/critic (`FUGUE_PREFLIGHT_PARALLEL_ENABLED`, timeout: `FUGUE_PREFLIGHT_PARALLEL_TIMEOUT_SEC`)
