# Portable Phase Artifact Contract v1

## Goal

`Kernel` と現行 `FUGUE` の双方で使える、provider-agnostic な `phase artifact` 可視化契約を定義する。

この文書の目的は、`Claude Code` 固有の実行機構を導入することではなく、
既存の phase gate / compact artifact / runner 契約の上に、
機械可読で fail-closed な handoff 面を追加することである。

## Terms

### Portable

この文書における `portable` とは次を意味する。

- `Claude Code` 固有 primitive に依存しない
- 特定 provider の prompt/runtime 文法に依存しない
- 既存の shell runner / ledger / compact artifact から検証できる

`portable` は「任意の外部 runtime にそのまま移植可能」を意味しない。

### Formalize

この文書における `formalize` とは次を意味する。

- artifact key を明示する
- phase ごとの required / optional を明示する
- runtime script が機械的に検証できる
- regression test で失敗条件を固定する

## Scope

この文書が定義するのは、`phase_artifacts` の要件だけである。

- compact artifact に phase artifact path をどう持つか
- phase completion で何を最低限チェックするか
- どの phase でどの artifact key を required にするか
- workflow caller からの `kernel_run_id` 伝播をどこまで正規パスとして扱うか
- FUGUE workflow 側の compact artifact 更新をどこまで single-writer として許可するか

この文書は以下を再定義しない。

- 現行 FUGUE control plane ownership
- provider resolution
- lane topology / quorum
- MCP ownership
- bootstrap receipt / runtime ledger の state meaning

## Authority Boundary

- 現行 FUGUE runtime の SSOT は [AGENTS.md](/Users/masayuki_otawara/fugue-orchestrator/AGENTS.md)
- Kernel interface schema の SSOT は [schema-v1.md](/Users/masayuki_otawara/fugue-orchestrator/docs/kernel/interfaces/schema-v1.md)
- behavioral contract の SSOT は [contracts.md](/Users/masayuki_otawara/fugue-orchestrator/docs/kernel/interfaces/contracts.md)
- write scope boundary の SSOT は [track-compat.md](/Users/masayuki_otawara/fugue-orchestrator/docs/kernel/interfaces/track-compat.md)

本書は上記を参照し、specialized requirement として補完する。

## Shared AGENTS / Adapter Boundary

`Claude Code` / `FUGUE` / `Kernel` が互いに領空侵犯しないため、shared layer は次に限定する。

1. `AGENTS.md` は共有憲法であり、唯一の上位 SSOT とする
2. `CLAUDE.md` / `CODEX.md` は thin adapter とし、role-specific delta と pointer だけを持つ
3. 新しい `shared agent.md` を第二の憲法として追加してはならない
4. 共有してよいのは provider-agnostic な contract / schema / boundary rule のみとする
5. Claude Code 固有の agent/skill 定義は Claude adapter 側に閉じる
6. Kernel 固有の lane / receipt / guard 契約は Kernel 側に閉じる
7. cross-domain handoff は明示的で監査可能な経路に限定する

この文書が扱う `phase artifact contract` は shared layer に属する。
ただし、その producer / consumer runtime は各 adapter/runtime が所有する。

## Problem

phase execution 自体は既に gate で管理されているが、
phase ごとの artifact 参照は runtime surface 間で一貫していない。

その結果、次の問題が残る。

- phase が完了しても、どの artifact が handoff truth かが compact artifact から見えにくい
- completion が通っても、required artifact path の欠落を明示できない場合がある
- provider/session の会話履歴に依存した暗黙 handoff が入り込みやすい

## Goals

1. phase artifact 参照を compact artifact に machine-readable に残す
2. required artifact が無い phase completion を fail-closed にする
3. artifact content ではなく artifact path だけを handoff 面に置く
4. FUGUE と Kernel の境界を崩さず、既存 runner 経路をそのまま使う
5. bounded な追加だけで可観測性を上げる
6. caller 未対応時や compact 未存在時に、安全に no-op で止まる

## Non-Goals

- `context:fork` / `!command` / `subagent:` の採用
- direct prompt-embedded CLI execution の導入
- full workflow redesign
- provider routing / consensus / MCP policy の変更
- compact artifact に大きな本文や reasoning を埋め込むこと

## Invariants

次は v1 の不変条件である。

1. `phase_artifacts` は additive field であり、既存 compact artifact field を壊さない
2. `phase_artifacts` は path string のみを保持し、artifact content を inline しない
3. compact artifact の更新 event は既存 contract を維持する
4. required artifact check は deterministic で phase-specific である
5. 実行は既存 runner / control-plane path に残し、artifact 契約だけを追加する
6. `kernel_run_id` は明示 input でのみ受理し、推測や自動補完をしてはならない
7. FUGUE workflow から compact artifact を更新する writer は single-writer でなければならない
8. caller が `kernel_run_id` を渡さない時は no-op とし、新規 compact artifact を生成してはならない
9. context hygiene を守るため、artifact body / summary 本文 / reasoning を `phase_artifacts` 経路に混入させてはならない

## Contract

### Compact Artifact Field

`compact artifact` は v1 で次の additive field を持ってよい。

```json
{
  "phase_artifacts": {
    "research_report_path": "...",
    "plan_report_path": "...",
    "critic_report_path": "...",
    "preflight_report_path": "...",
    "implementation_report_path": "...",
    "todo_report_path": "...",
    "lessons_report_path": "..."
  }
}
```

### Field Rules

- key は stable name を使う
- value は file-system path string とする
- key が不要な run では absent でよい
- path normalization は v1 の required ではない
- ただし producer は deterministic に同じ key 名を使うこと
- value は path reference に限定し、markdown 本文・要約本文・diff 本文・推論本文を入れてはならない

### Caller Propagation Boundary

`kernel_run_id` を伴う `phase_artifacts` 伝播は、v1 では次の境界でのみ正規パスとみなす。

- human または上位 orchestrator が `workflow_dispatch` / `workflow_call` input として明示的に渡した `kernel_run_id`
- caller workflow から callee workflow への明示 pass-through
- callee workflow が成功条件を満たした後に実施する compact artifact 更新

次は v1 で禁止または非対応とする。

- `github.run_id`、issue 番号、dispatch nonce、その他の workflow metadata から `kernel_run_id` を推測すること
- input 不在時に代替 run id を自動生成して compact artifact を更新すること
- caller が未対応のまま暗黙に propagation を始めること
- `canary_dispatch_run_id` 等の既存 workflow 識別子を `kernel_run_id` の代替として扱うこと

### FUGUE Workflow Writer Ownership

現行 FUGUE runtime で `phase_artifacts` を compact artifact に反映する場合、
v1 では workflow 側 single-writer を原則とする。

- producer script は artifact path を emit してよい
- compact artifact の更新は workflow 側の明示ステップでのみ実施してよい
- 同一 event/phase について producer script と workflow step の二重書き込みをしてはならない
- FUGUE control plane の既存責務
  (`route`, `dispatch`, issue update, PR creation, artifact upload)
  を Kernel 側の都合で再定義してはならない

### Required Artifact Keys by Phase

v1 で required にする phase は最小に限定する。

- `plan` -> `plan_report_path`
- `critique` -> `critic_report_path`
- `implement` -> `implementation_report_path`

以下は v1 では optional とする。

- `requirements`
- `simulate`
- `verify`

### Completion Semantics

`phase-gate complete <phase>` は以下で fail-closed とする。

1. required key が env / compact artifact のどちらにも存在しない
2. required key の path が存在しない file を指す

failure reason は explicit でなければならない。

例:

- `phase-artifact-missing:<key>`
- `phase-artifact-path-missing:<key>`

### Workflow-side No-op / Fail-closed Semantics

FUGUE workflow が compact artifact へ `phase_artifacts` を反映する場合、
v1 の挙動は次の通りとする。

1. `kernel_run_id` が空または caller から未伝播なら no-op
2. compact artifact が存在しないなら no-op
3. implementation runner が失敗したなら no-op
4. required artifact path が空または欠落しているなら no-op
5. `phase-gate complete <phase>` は required artifact 欠落時に fail-closed

ここでの no-op は「既存 FUGUE 実行を継続しつつ compact artifact を更新しない」ことを意味する。
no-op は新たな compact artifact を生成する根拠にはならない。

## Security and Governance Constraints

次は必須である。

- artifact path は reference だけを運ぶ
- external provider への file content 転送経路を新設しない
- control-plane ownership を bypass する direct execution を導入しない
- single-lane fallback を正当化しない
- adapter file に長い policy text を複製しない
- shared layer に Claude 固有または Kernel 固有の runtime primitive を入れない
- `kernel_run_id` の伝播を shared layer の一般義務に拡張しない
- context pressure を上げる artifact body 複製を追加しない
- compact artifact の `summary` / `decisions` / `next_action` の bounded contract を `phase_artifacts` 追加で弱めない
- workflow から compact artifact へ書く summary は bounded な milestone note に限り、artifact 本文の代替面にしてはならない

## Ownership Matrix

v1 における ownership は次で固定する。

| Surface | Owner | Allowed action | Forbidden action |
|---|---|---|---|
| `kernel_run_id` issuance | human / top-level orchestrator | 明示 input として発行する | workflow metadata から推測する |
| caller workflow (`fugue-caller`, `fugue-task-router`, `fugue-tutti-caller`) | FUGUE control plane | 明示 pass-through | run id を mint / rewrite する |
| producer script | runner-owned script | artifact path を emit する | compact artifact を直接更新する |
| workflow propagation step | workflow single-writer | bounded な `phase_artifacts` path reference を追記する | `phase_completed` truth を代行する |
| `kernel-phase-gate` | Kernel runtime | required artifact を検証して `phase_completed` を確定する | caller 伝播の代替になる |
| `kernel-compact-artifact.sh` | shared mutation surface | additive field を merge する | artifact body を inline する |

この matrix を外れる変更は v1 の範囲外とし、replan を要求する。

### Artifact Key Ownership

artifact key 単位の責務は v1 で次のように固定する。

| Key | Producer | Consumer | Validator | v1 status |
|---|---|---|---|---|
| `research_report_path` | preflight / research producer | compact readers / restart surface | none | optional |
| `plan_report_path` | planning producer | compact readers / workflow propagation | `kernel-phase-gate` | required for `plan` |
| `critic_report_path` | critique producer | compact readers / workflow propagation | `kernel-phase-gate` | required for `critique` |
| `preflight_report_path` | implementation runner | compact readers | none | optional |
| `implementation_report_path` | implementation runner | compact readers / workflow propagation | `kernel-phase-gate` | required for `implement` |
| `todo_report_path` | implementation runner | operator / restart surface | none | optional |
| `lessons_report_path` | implementation runner | operator / lessons flow | none | optional |

この表にない key は v1 shared contract に追加してはならない。

## Trigger Matrix

v1 における trigger と許可挙動は次で固定する。

| Trigger | `kernel_run_id` source | Gate | Pass branch | Failure / no-op branch |
|---|---|---|---|---|
| local Kernel phase completion | 既存 Kernel run | `kernel-phase-gate` | `phase_completed` を確定 | fail-closed |
| `workflow_dispatch` / `workflow_call` with explicit `kernel_run_id` | human / upstream orchestrator input | workflow propagation step | bounded な path reference を compact に追記 | no-op |
| caller 未対応 / `kernel_run_id` 空 | なし | workflow propagation step | none | no-op |
| compact artifact 不在 | 既存 input はある | workflow propagation step | none | no-op |
| implementation runner failed | 既存 input はある | workflow propagation step | none | no-op |
| required artifact path empty / missing | 既存 input はある | workflow propagation step | none | no-op |
| `fugue-bridge` / canary / legacy path | runtime-specific | runtime-specific | v1 非対象 | shared contract を拡張しない |

この matrix に含まれない trigger は v1 では unsupported とみなす。

## Traceability Matrix

v1 requirements の handoff 面は、少なくとも次で追跡できなければならない。

| Requirement | Enforcement owner | Runtime surface | Regression evidence |
|---|---|---|---|
| `kernel_run_id` は明示 input のみ | caller workflow / handoff | `fugue-caller` / `fugue-task-router` / `route-task-handoff.sh` / `fugue-tutti-caller` | `tests/test-route-task-handoff.sh` |
| workflow propagation は single-writer | workflow step | `fugue-codex-implement.yml` | `tests/test-fugue-codex-implement-kernel-artifacts.sh` |
| required artifact 欠落時は no-op | workflow step | `fugue-codex-implement.yml` | `tests/test-fugue-codex-implement-kernel-artifacts.sh` |
| `complete plan|critique|implement` は fail-closed | Kernel phase gate | `scripts/lib/kernel-phase-gate.sh` | `tests/test-kernel-phase-gate.sh` |
| compact artifact は path-only / bounded | compact mutation surface | `scripts/lib/kernel-compact-artifact.sh` | `tests/test-kernel-compact-artifact.sh` |

この traceability を満たさない要件は v1 では未受理とみなす。

## Requirement Linkage Matrix

critical rule の相互参照は次で固定する。

| Rule | Invariant | Acceptance | Rollout | Regression evidence |
|---|---|---|---|---|
| `kernel_run_id` は明示 input のみ | #6 | #7, #8 | Phase 5 | `tests/test-route-task-handoff.sh` |
| workflow propagation は single-writer | #7 | #9 | Phase 2 | `tests/test-fugue-codex-implement-kernel-artifacts.sh` |
| required artifact path 欠落時は no-op / phase gate は fail-closed | #4, #8 | #3, #8 | Phase 3 | `tests/test-fugue-codex-implement-kernel-artifacts.sh`, `tests/test-kernel-phase-gate.sh` |
| path-only / bounded compact | #1, #2, #9 | #10 | Phase 2 | `tests/test-kernel-compact-artifact.sh` |
| implementation handoff が shared contract を超えない | #5, #7 | #4, #11 | Phase 2-5 | doc review + above regression set |

## Acceptance Criteria

v1 は次を満たした時に受理できる。

1. dedicated requirements doc が存在する
2. compact artifact が `phase_artifacts` を保持できる
3. `complete plan|critique|implement` が required artifact 無しで落ちる
4. existing provider/lane evidence contract が変わらない
5. regression test が success / missing-artifact failure を固定する
6. Claude-specific runtime dependency が追加されていない
7. caller が `kernel_run_id` を渡した時だけ workflow-side propagation が有効になる
8. caller 未対応時、compact artifact 未存在時、runner 失敗時、required path 欠落時は no-op である
9. workflow-side propagation は single-writer として定義され、producer script は compact artifact を直接更新しない
10. `phase_artifacts` 経路に本文 inline が混入しない
11. ownership / trigger / traceability matrix が存在し、実装 handoff の判断材料になる

## Freeze Status

この文書は `v1 frozen` とする。

- v1 の対象は `phase_artifacts` handoff 契約の最小核だけである
- Acceptance Criteria を満たした時点で、v1 requirements は complete とみなす
- 下記の follow-up は `deferred but non-blocking` であり、v1 の受理を妨げない
- v1 の shared contract を変更する場合は replan を必須とする

## Rollout

### Phase 1

この requirements doc を追加する。

### Phase 2

compact artifact に `phase_artifacts` を additive field として入れる。

### Phase 3

`plan` / `critique` / `implement` だけに required artifact completion check を入れる。

### Phase 4

運用と test が安定した後に、`requirements` / `simulate` / `verify` の拡張要否を再評価する。

### Phase 5

caller 伝播の適用範囲を広げる場合は、
`workflow_dispatch` / `workflow_call` のどの入口が `kernel_run_id` を明示受理するかを
先に requirements へ追加してから実装する。

## Explicit Non-Portable Patterns

次は reference として読むだけで、採用しない。

- `Claude Code` skill loader
- `context:fork`
- `!command` expansion
- `subagent:` frontmatter
- prompt-only safety rule

## Open Follow-Ups

次は `deferred but non-blocking` な v2 候補であり、v1 requirements の未完了を意味しない。

1. `simulate` / `verify` の required artifact key を追加するか
2. path safety rule を v2 で stricter にするか
3. runner から compact artifact への artifact key 書き込みを自動化するか
4. `kernel_run_id` pass-through をどの caller まで広げるか
