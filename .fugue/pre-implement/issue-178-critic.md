# Issue #178 Critic Artifact

## Observations
- The `implement` job unconditionally runs the `Run parallel preflight nodes` step (defaulting `FUGUE_PREFLIGHT_PARALLEL_ENABLED=true`), spins up `research/plan/critic` worktrees, and forces each node to write exactly one artifact along with a summary log directory that is exported downstream (`research_report_path`, `plan_report_path`, `critic_report_path`, `parallel_preflight_log_dir`). This guarantees the artifacts exist before the main Codex loop and provides recovery stubs plus degradation tracking when a node fails to produce its file (`.github/workflows/fugue-codex-implement.yml:278-419`).
- The subsequent `codex exec` invocation reuses those artifact paths, injects the context budget guidance/guard hints directly into the instruction text (initial ≤ X, guard applied flag, and floor/span values), and then enforces the artifacts during protocol validation, failing the workflow if `research`, `plan`, or `critic` reports are missing (`.github/workflows/fugue-codex-implement.yml:544-710`).
- The `workflow-risk-policy.sh` helper that feeds `prepare` exposes the context-over-compression guard: it computes risk-based initial/max budgets, clamps them to globally configurable floors, enforces a minimum span, and emits `context_budget_guard_applied` plus specific reasons whenever it raises a value. That guarantees downstream stages never see budgets tighter than the guard thresholds (`scripts/lib/workflow-risk-policy.sh:188-279`).

## Failure Scenarios
- A Codex node crash/time-out still yields an artifact (fallback placeholder) and increments `parallel_failures`, but a degraded summary file is written so the downstream run knows the preflight node needs re-running with concrete findings (`.github/workflows/fugue-codex-implement.yml:351-418`).
- If any of the parallel artifacts disappear before the main Codex loop begins, the workflow forces `EXIT_CODE=1` and comments/logs the missing file names, ensuring the overall job clearly fails instead of silently proceeding (`.github/workflows/fugue-codex-implement.yml:662-710`).
- When someone tries to shrink context budgets below the enforced floors or span, the guard raises the values, sets `context_budget_guard_applied=true`, and records the reason string (e.g., `raised-initial-floor`, `raised-span-floor`), so misconfiguration or regression in floor constants immediately surfaces in the `prepare` output (`scripts/lib/workflow-risk-policy.sh:225-279`).

## Guardrails & Regression Checks
- Regression: keep verifying that the `Run parallel preflight nodes` step still exports the artifact paths/log dir and that `codex exec` fails fast if any of the `.fugue/pre-implement/issue-<n>-research|plan|critic.md` files vanish, ensuring the acceptance criteria stay satisfied (`.github/workflows/fugue-codex-implement.yml:278-710`).
- Regression: add a lightweight shim (or unit test) around `scripts/lib/workflow-risk-policy.sh` to run it with intentionally low inputs and assert that it returns `context_budget_guard_applied=true` plus the corresponding reason, keeping the over-compression guard intact (`scripts/lib/workflow-risk-policy.sh:188-279`).

