# Source: AGENTS.md §8 — Simulation Runbook
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 8. Simulation Runbook

Use deterministic simulation before changing orchestration logic:

```bash
scripts/sim-orchestrator-switch.sh
```

Simulation common rule:
- `FUGUE_SIM_CODEX_SPARK_ONLY=true` (default) forces simulation to run `codex-main` and codex multi-agent lanes on `gpt-5.3-codex-spark` for faster turnaround.
- Set `FUGUE_SIM_CODEX_SPARK_ONLY=false` only when main-model parity testing against `gpt-5.4` is explicitly required.

Use live rehearsal only when needed and clean up synthetic issues after verification.
