# Kernel Boundary Guard

FUGUE refactor が Kernel execution substrate を汚染しないための安全規則。

## 触る前に Kernel 影響確認が必須なファイル

### Tier 1: 絶対確認（変更前に必ず Kernel 契約を読む）
- `AGENTS.md` — FUGUE SSOT。変更は repo 全体の運用原則を変える
- `CODEX.md` — Kernel adapter。AGENTS.md と噛み合わなくなると Kernel 入口が壊れる
- `docs/kernel/requirements-freeze-v1.md` — Kernel 非ゴールと handoff 契約

### Tier 2: 要注意（shared contract 経由で Kernel に波及）
- `rules/shared-orchestration-playbook.md` — 共有 playbook
- `scripts/harness/route-task-handoff.sh` — handoff_target=kernel|fugue-bridge 境界
- `scripts/harness/fugue-bridge-handoff.sh` — legacy bridge
- `scripts/harness/run-recovery-console.sh` — recovery 導線境界

### Tier 3: 間接影響（workflow 契約変更時のみ）
- `.github/workflows/fugue-tutti-caller.yml` — start-signal 契約
- `.github/workflows/fugue-tutti-router.yml` — lane/quorum
- `.github/workflows/fugue-codex-implement.yml` — Codex sovereignty

## FUGUE refactor で安全に触れる主戦場
- FUGUE workflow 実装の内部ロジック
- FUGUE local orchestration 実装
- FUGUE 固有 docs（kernel- prefix なし）
- scripts/lib/kernel-*.sh（Kernel 自身のライブラリ — Kernel 側の改善は安全）

## 原則
- shared contract を触る変更は Kernel doctrine 汚染リスク
- AGENTS.md 変更は必ず CODEX.md との整合性を確認
- Kernel 要件は FUGUE runtime を壊さないことを非ゴールとして固定済み
