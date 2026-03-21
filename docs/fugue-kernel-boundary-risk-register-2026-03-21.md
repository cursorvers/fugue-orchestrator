# FUGUE Kernel Boundary Risk Register 2026-03-21

## Summary

FUGUE の大規模リファクタは、現時点では Kernel に致命傷を与えている証拠はない。  
ただし、shared contract を触る変更は Kernel に波及しやすい。

評価メモ:

- `FUGUE orchestration`: `87/100`
- `Kernel orchestration`: `81/100`
- `FUGUE refactor -> Kernel` 悪影響リスク: `31/100`
- 境界健全性: `72/100`

## Highest Risk Files

- [AGENTS.md](/Users/masayuki_otawara/fugue-orchestrator/AGENTS.md)
  - 現行 FUGUE / GitHub workflow の SSOT
- [CODEX.md](/Users/masayuki_otawara/fugue-orchestrator/CODEX.md)
  - Kernel adapter
- [requirements-freeze-v1.md](/Users/masayuki_otawara/fugue-orchestrator/docs/kernel/requirements-freeze-v1.md)
  - Kernel の非ゴールと handoff 契約

## High Risk Shared Contracts

- [shared-orchestration-playbook.md](/Users/masayuki_otawara/fugue-orchestrator/rules/shared-orchestration-playbook.md)
- [run-local-orchestration.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/local/run-local-orchestration.sh)
- [fugue-tutti-caller.yml](/Users/masayuki_otawara/fugue-orchestrator/.github/workflows/fugue-tutti-caller.yml)
- [fugue-tutti-router.yml](/Users/masayuki_otawara/fugue-orchestrator/.github/workflows/fugue-tutti-router.yml)
- [fugue-codex-implement.yml](/Users/masayuki_otawara/fugue-orchestrator/.github/workflows/fugue-codex-implement.yml)

## Boundary Scripts To Watch

- [route-task-handoff.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/harness/route-task-handoff.sh)
- [fugue-bridge-handoff.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/harness/fugue-bridge-handoff.sh)
- [run-recovery-console.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/harness/run-recovery-console.sh)

## Lower Risk

- [mbp-macmini-tmux-operations-manual.md](/Users/masayuki_otawara/fugue-orchestrator/docs/mbp-macmini-tmux-operations-manual.md)
- [local-codex-handoff-2026-03-21.md](/Users/masayuki_otawara/fugue-orchestrator/docs/local-codex-handoff-2026-03-21.md)
- [dr-continuation-runbook-v1.md](/Users/masayuki_otawara/fugue-orchestrator/docs/kernel/dr-continuation-runbook-v1.md)

## Practical Rule

FUGUE refactor で最も危険なのは、shared contract を FUGUE 都合だけで変更すること。  
特に `AGENTS.md`, `CODEX.md`, `docs/kernel/*`, `route-task-handoff.sh` を触る変更は、Kernel 影響確認を必須にする。
