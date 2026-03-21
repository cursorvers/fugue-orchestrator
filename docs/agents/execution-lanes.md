# Source: AGENTS.md §4 — Execution/Evaluation Lanes
# SSOT: This content is authoritative. AGENTS.md indexes this file.

## 4. Execution/Evaluation Lanes

- Core quorum: 6 lanes minimum (Codex3 + GLM3).
- `FUGUE_MIN_CONSENSUS_LANES` (default `6`) is a hard floor; lane matrix resolution fails fast when the configured floor is not met.
- Add one main-provider signal lane after resolution:
  - `codex-main-orchestrator` when main is `codex`
  - `claude-main-orchestrator` when main is `claude`
- In Hybrid Conductor Mode (main != execution_provider), implementation dispatch always uses `codex-full` profile regardless of main provider.
- `FUGUE_DUAL_MAIN_SIGNAL=true` (default) adds the opposite main signal lane as a secondary vote signal.
- Execution profile is resolved per run:
  - Primary: `subscription-strict` (`FUGUE_CI_EXECUTION_ENGINE=subscription` + online self-hosted runner with required label `FUGUE_SUBSCRIPTION_RUNNER_LABEL`)
  - Offline hold: `subscription-paused` (`FUGUE_SUBSCRIPTION_OFFLINE_POLICY=hold`)
  - Continuity fallback: `api-continuity` (`FUGUE_SUBSCRIPTION_OFFLINE_POLICY=continuity`, default, or emergency continuity mode)
- `FUGUE_EMERGENCY_CONTINUITY_MODE=true` enables inflight-only processing on GitHub-hosted runners.
- Continuity fallback demotes assist `claude` using `FUGUE_EMERGENCY_ASSIST_POLICY` (default `none`) unless forced.
- Strict guards (`FUGUE_STRICT_MAIN_CODEX_MODEL`, `FUGUE_STRICT_OPUS_ASSIST_DIRECT`) are enforced in `subscription-strict` and disabled by default in API continuity mode unless `FUGUE_API_STRICT_MODE=true`.
- `FUGUE_REQUIRE_DIRECT_CLAUDE_ASSIST=true` enables hard gate for `claude-opus-assist` direct success in `/vote` integration (default disabled).
- `FUGUE_REQUIRE_CLAUDE_SUB_ON_COMPLEX=true` enforces Claude sub gate on complex tasks (`risk_tier=high` or ambiguity translation-gate=true) **when assist is `claude`**; missing Claude Opus assist success turns `ok_to_execute=false` (default enabled).
- `FUGUE_REQUIRE_BASELINE_TRIO=true` enforces baseline trio success (`codex` + `claude` + `glm`) before execution approval (default enabled).
- Multi-agent depth baseline is controlled by `FUGUE_MULTI_AGENT_MODE=standard|enhanced|max` (default `enhanced`), with complexity-based downshift/upshift when no explicit override is present.
- Codex lane model split:
- `FUGUE_CODEX_MAIN_MODEL` for `codex-main-orchestrator` (default `gpt-5.4`)
  - `FUGUE_CODEX_MULTI_AGENT_MODEL` for non-main codex lanes (default `gpt-5.3-codex-spark`)
- GLM baseline model: `glm-5.0`.
- `FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=true` (default) keeps GLM baseline voters active even when `FUGUE_CI_EXECUTION_ENGINE=subscription` (hybrid: codex/claude via CLI, GLM via API).
- Codex recursive delegation (`parent -> child -> grandchild`) can be enabled per-lane:
  - `FUGUE_CODEX_RECURSIVE_DELEGATION` (`true|false`, default `true` since v8.5)
  - `FUGUE_CODEX_RECURSIVE_MAX_DEPTH` (minimum `2`, default `2` since v8.5, previously `3`)
  - `FUGUE_CODEX_RECURSIVE_TARGET_LANES` (CSV lane list or `all`, default `codex-main-orchestrator,codex-orchestration-assist`)
  - `FUGUE_CODEX_RECURSIVE_DRY_RUN` (`true|false`, default `false`, synthetic verification mode)
  - Implementation timeout extended to 90 minutes when recursive delegation is active.
- GLM subagent fan-out is controlled by `FUGUE_GLM_SUBAGENT_MODE=off|paired|symphony` (default `symphony` since v8.5, previously `paired`).
  - `paired`: adds GLM orchestration subagent lane and mirrors architect/plan checks in enhanced/max.
  - `symphony`: adds the above plus GLM reliability subagent in max mode (v8.5 default; adds `glm-reliability-subagent` lane).
  - When `FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=false`, subscription mode forces GLM subagent fan-out to `off`.
  - `*-subagent` lanes are optional/non-blocking on provider-side API failure.
- When assist is `claude` and state is not `exhausted`, add Claude assist lanes (Opus + Sonnet).
- Local direct orchestration (`scripts/local/run-local-orchestration.sh`) enforces `claude-opus-assist` direct success when either:
  - `assist=claude`, `FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST=true`, and `FUGUE_CLAUDE_RATE_LIMIT_STATE=ok` (legacy direct gate), or
  - `assist=claude`, `FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST_ON_COMPLEX=true`, and task is complex (`risk_tier=high` or `FUGUE_LOCAL_AMBIGUITY_SIGNAL=true`) (default enabled).
- In `FUGUE_CLAUDE_MAX_PLAN=true` mode without `ANTHROPIC_API_KEY`, Claude assist lanes run through Codex proxy and remain vote participants.
- Optional specialist lanes:
  - Gemini for UI/UX and visual intent (including subscription when `FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=true`).
  - xAI for X/Twitter and realtime intent.
- Optional lane failures are non-blocking for quorum totals.
