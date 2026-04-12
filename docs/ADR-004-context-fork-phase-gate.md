# ADR-004: context:fork Phase Gate PoC

## Status: ACCEPTED (PoC implemented 2026-03-22)

## Date: 2026-03-22

## Context

ADR-003 で context:fork の FUGUE 適用を「1 phase で PoC」と判断。
plan phase のみで context:fork を spawn ベースと比較検証する。

## Decision

plan phase 用の context:fork skill を作成し、spawn ベースとの比較を行う。

## Requirements

| ID | 要件 | 優先度 |
|----|------|--------|
| P3-R1 | ~/.claude/skills/fugue-phase-fork/SKILL.md 新規作成 | MUST |
| P3-R2 | context: fork で plan phase を独立コンテキスト実行 | MUST |
| P3-R3 | $ARGUMENTS から task を受取り plan を生成 | MUST |
| P3-R4 | !command で fugue-lane-bridge.mjs を呼出し結果注入 | MUST |
| P3-R5 | subagent: 不使用 | MUST |
| P3-R6 | 出力: { lanes, recommendation, risks } JSON | MUST |
| P3-R7 | spawn ベースとの比較可能性 | SHOULD |
| P3-R8 | 40行以内 | SHOULD |

## Acceptance Criteria

1. /fugue-phase-fork "task" で plan 生成
2. 親コンテキストに影響しない
3. spawn と同等以上の plan 品質
4. subagent 不使用
5. syntax check pass

## Not In Scope

- simulate/critique の fork 化
- 全 phase gate の移行
- Kernel への展開
