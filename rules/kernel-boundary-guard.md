# Kernel Boundary Guard

FUGUE refactor が Kernel execution substrate を汚染しないための安全規則。
Codex (Kernel guardian) レビュー済み (2026-03-21)。

## 触る前に Kernel 影響確認が必須なファイル

### Tier 1: 絶対確認（変更前に必ず Kernel 契約を読む）
- `AGENTS.md` — FUGUE SSOT。変更は repo 全体の運用原則を変える
- `CODEX.md` — Kernel adapter。AGENTS.md と噛み合わなくなると Kernel 入口が壊れる
- `docs/kernel/requirements-freeze-v1.md` — Kernel 非ゴールと handoff 契約
- `.codex/prompts/kernel.md` — Kernel bootstrap prompt authority
- `.codex/prompts/k.md` — `/k` alias contract
- `docs/kernel-unattended-runtime-substrate.md` — sovereign core と runtime substrate の責務境界

### Tier 2: 要注意（shared contract 経由で Kernel に波及）
- `rules/shared-orchestration-playbook.md` — 共有 playbook
- `scripts/harness/route-task-handoff.sh` — handoff_target=kernel|fugue-bridge 境界
- `scripts/harness/fugue-bridge-handoff.sh` — legacy bridge
- `scripts/harness/run-recovery-console.sh` — recovery 導線境界
- `codex-kernel-guard` authority surface — `launch`, `doctor`, `recover-run`, `phase-check`, `phase-complete`, `run-complete` の bootstrap/evidence/restart handoff contract

### Tier 3: 間接影響（shared identifier/start-signal 変更時のみ）
- `.github/workflows/fugue-tutti-caller.yml` — start-signal 契約
- `.github/workflows/fugue-tutti-router.yml` — lane/quorum
- `.github/workflows/fugue-codex-implement.yml` — legacy FUGUE implementation path（Kernel sovereignty の source ではない）

## FUGUE refactor で安全に触れる主戦場
- FUGUE workflow 実装の内部ロジック
- FUGUE local orchestration 実装
- FUGUE 固有 docs（kernel- prefix なし）
- `scripts/lib/kernel-*.sh` — 原則 Kernel 側の改善領域。ただし bootstrap, tmux handoff, compact, doctor/recover, evidence gate, three-voice contract に触れる変更は Tier 1/Tier 2 扱い

## Kernel 不可侵契約

### tmux substrate independence
- `1 request = 1 Kernel run`
- `1 tmux session = 1 Kernel run = 1 Codex thread`
- `purpose is fixed per run` — materially 変わるなら新 run を作る
- FUGUE refactor でこの 1:1:1 対応を壊してはならない

### compact/doctor/recover autonomy
- `doctor` は read-only display surface
- `recover-run` は compact state から heavy tmux session を再生成
- `doctor → doctor --run → recover-run` は最小継続導線
- FUGUE refactor はこの回復導線に FUGUE 固有の control-plane 依存を追加してはならない

### three-voice integrity
- normal shape: `Codex latest + GLM + specialist 1`
- GLM 不調時は specialist で代替、GLM recovery は並列進行
- required model evidence を phase gate で確認
- valid な three-voice shape を作れない場合は **fail-closed**

### sovereignty
- `Kernel sovereign core decides; runtime substrate runs`
- GitHub Actions は backup/audit/milestone marker/external mirror only — main execution substrate に昇格させてはならない
- FUGUE workflow は Kernel の control-plane judgment, quorum, ok_to_execute を所有しない

## 原則
- shared contract を触る変更は Kernel doctrine 汚染リスク（ただし runtime primitive の取り込みまで萎縮する必要はない）
- AGENTS.md 変更は必ず CODEX.md との整合性を確認
- Kernel 要件は FUGUE runtime を壊さないことを非ゴールとして固定済み
