# Source: AGENTS.md §8 — Simulation Runbook
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 8. Simulation Runbook

Use deterministic simulation before changing orchestration logic:

```bash
scripts/sim-orchestrator-switch.sh
```

Simulation common rule:
- `FUGUE_SIM_CODEX_SPARK_ONLY=false` (default) keeps main-model and role-lane diversity so codex-spark rate limits do not stop simulation.
- Set `FUGUE_SIM_CODEX_SPARK_ONLY=true` only for short, speed-first checks that can tolerate codex-spark quota exhaustion.

Use live rehearsal only when needed and clean up synthetic issues after verification.
