# Public Repository Safety Notes (Cursorvers / FUGUE)

Date: 2026-02-14

This note records the agreed guardrails for operating `cursorvers/fugue-orchestrator` as a **public** repository while still running GitHub Actions-based orchestration.

## Summary
- Public visibility is acceptable **as long as** untrusted users cannot trigger workflows that consume secrets or mutate repos.
- The main risk is not "followers", but "anyone can open issues/comments" causing automation to run or spam.

## Must Hold (Invariants)
- **Trust gate before secrets**: any path that uses `${{ secrets.* }}` must require the actor to be trusted (`write|maintain|admin`).
- **No `pull_request_target`** in orchestration workflows (avoid running with elevated token on untrusted PR content).
- **Least privilege for strong tokens**:
  - Keep high-blast-radius tokens (PAT, deploy tokens) scoped to the minimum set of repos that need them.
  - Do not set strong tokens as org secrets with visibility `ALL` unless you explicitly accept the blast radius.
- **Keep the trusted set small**: minimize who gets repo write access (this defines the “trusted” population).

## Red Flags (Stop and Review)
- Adding a new workflow trigger that allows outsiders to reach a secret-consuming step:
  - `issues` / `issue_comment` / `workflow_dispatch` without a trust check
  - Any workflow that can be dispatched by untrusted users and still accesses secrets
- Introducing `pull_request_target` or any PR-trigger that checks out attacker-controlled code with write tokens.
- Moving from `github.token` to PAT-like tokens without explicit constraints and review.

## Quick Self-Check Commands
Run these before/after any workflow changes:

```bash
# No PR-target usage in orchestration
rg -n "pull_request_target" .github/workflows -S

# Find secret usage sites (ensure they are behind trust gates)
rg -n "secrets\\." .github/workflows -S

# Find trust gates (ensure new paths reuse these patterns)
rg -n "write\\|\\|.*maintain\\|\\|.*admin|trusted" .github/workflows -S
```

## Current (Expected) Guardrails in This Repo
- `fugue-task-router` and `fugue-tutti-router` require author permission `write|maintain|admin` for mainframe handoff / execution.
- Cross-repo mutation requires `TARGET_REPO_PAT`; missing PAT should result in `needs-human` and no further automation.

