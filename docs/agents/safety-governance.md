# Source: AGENTS.md §5 — Safety and Governance
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 5. Safety and Governance

- High-risk finding blocks auto-execution and escalates to human review.
- Tutti execution decisions use weighted consensus (role-weighted 2/3 threshold) plus HIGH-risk veto.
- For both `claude` and `codex` main orchestrators, non-critical work uses Tutti / Kernel council
  approval as the authorization path after `ok_to_execute=true`; do not add another routine user
  approval prompt when consensus evidence exists.
- Human approval remains mandatory only for critical, destructive, irreversible,
  secrets/auth/billing/trust-boundary, materially ambiguous, or high-impact external side-effect
  actions without rollback.
- Review-only intent must clear stale implementation labels.
- Natural-language/mobile intake defaults to `review`; implement requires explicit signal.
- Implementation execution requires `implement`; `implement-confirmed` is required only for
  critical/high-risk implementation after consensus approval.
- Cross-repo implementation requires `TARGET_REPO_PAT`.
- Dangerous operations require explicit human consent paths.
- Implement mode must complete preflight refinement loops before code changes:
  1) Plan
  2) Parallel Simulation
  3) Critical Review
  4) Problem Fix
  5) Replan
  Repeat default 3 cycles (`FUGUE_IMPLEMENT_REFINEMENT_CYCLES=3`).
- After preflight passes, implement mode must run implementation collaboration dialogue rounds:
  - `Implementer Proposal` -> `Critic Challenge` -> `Integrator Decision` -> `Applied Change` -> `Verification`
  - Default rounds: `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS=2` (or `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE=1` when `execution_profile` is `claude-light`; in Hybrid Conductor Mode, `execution_profile=codex-full` applies full rounds).
- Parallel Simulation and Critical Review are hard gates and must not be skipped.
- For large refactor/rewrite/migration tasks, each cycle must explicitly compare at least two candidates and include failure-mode/rollback checks (`large-refactor` label or task-text detection).
- Risk-tier policy (`low|medium|high`) adjusts minimum loop depth and default review fan-out; low-risk defaults should stay lightweight.
