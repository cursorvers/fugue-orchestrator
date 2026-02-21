# Requirements: Codex Main Orchestrator + Claude Opus Assist Orchestrator

## 1. Goal

Build an orchestration system where:
- Codex is the main orchestrator (control-plane owner).
- Claude Opus is an assist orchestrator (sidecar advisor).
- Orchestrator selection remains variable and auditable without breaking FUGUE operations.

## 2. Scope

In scope:
- Main/assist provider resolution in GitHub Actions.
- Claude rate-limit aware fallback.
- Assist lane integration as optional/non-blocking.
- Workflow observability for requested vs resolved providers.
- Documentation and CLI semantics updates.

Out of scope:
- Replacing Codex implementation engine.
- Full removal of compatibility labels in one release.
- Migrating every external/global policy file in this change.

## 3. Functional Requirements

FR-1 Main provider resolution:
- Main provider resolution order:
  1) issue label (`orchestrator:*`)
  2) issue body hint
  3) repo default (`FUGUE_MAIN_ORCHESTRATOR_PROVIDER` fallback to `FUGUE_ORCHESTRATOR_PROVIDER`)
  4) hard fallback `codex`

FR-2 Assist provider resolution:
- Assist provider must resolve from:
  1) issue label (`orchestrator-assist:*`) if present
  2) issue body hint (`assist orchestrator provider:`) if present
  3) repo default (`FUGUE_ASSIST_ORCHESTRATOR_PROVIDER`)
  4) hard fallback `claude`

FR-3 Claude throttle guard:
- If Claude rate-limit state is `degraded` or `exhausted`, main provider must auto-fallback to `codex` unless forced.
- If Claude rate-limit state is `exhausted`, assist provider `claude` must auto-fallback to `none` unless forced.
- If Claude rate-limit state is `ok` or `degraded`, Sonnet assist lanes should remain eligible.
- Force override must be explicit (`orchestrator-force:claude` / CLI force option).
- Fallback reason must be written to issue comments for auditability.

FR-4 Main ownership:
- Control-plane state transitions remain owned by main orchestrator workflows.
- Assist output is advisory and must not own state transitions.

FR-5 Assist lane behavior:
- Assist lane must be optional and non-blocking.
- Missing/failed assist provider credentials must not fail quorum.
- Assist lane failure should be reported as skipped/error in integrated comment.

FR-6 Backward compatibility:
- Existing `orchestrator_provider` workflow input remains supported.
- Existing issue labeling patterns continue to work.

## 4. Non-Functional Requirements

NFR-1 Reliability:
- No regression in review-only and implement modes.
- Mainframe continues when assist lane is unavailable.

NFR-2 Observability:
- Integrated comment must include requested/resolved main + assist profiles.
- Status/watchdog should expose assist/provider health signals where possible.

NFR-3 Context efficiency:
- Local policy entry files remain thin; avoid large duplicated policy blocks.
- SSOT policy file is used as primary reference.

## 5. Configuration Requirements

Required/optional repo variables:
- `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` (optional, default resolved to codex)
- `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER` (optional, default `claude`)
- `FUGUE_CI_EXECUTION_ENGINE` (`harness|api`, default `harness`; controls run-agents engine)
- `FUGUE_MULTI_AGENT_MODE` (`standard|enhanced|max`, default `enhanced`; controls lane depth)
- `FUGUE_CLAUDE_RATE_LIMIT_STATE` (`ok|degraded|exhausted`)
- `FUGUE_CLAUDE_MAX_PLAN` (`true|false`, default `true`; allows Claude assist lanes without direct Anthropic key by proxying through Codex)
- `FUGUE_CLAUDE_SONNET4_MODEL` (optional, default `claude-3-7-sonnet-latest`)
- `FUGUE_CLAUDE_SONNET6_MODEL` (optional, default `claude-3-5-sonnet-latest`)

Secrets:
- Existing: `OPENAI_API_KEY`, `ZAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`
- Optional: `ANTHROPIC_API_KEY` for direct Claude API lane execution (not required when `FUGUE_CLAUDE_MAX_PLAN=true`)

## 6. Acceptance Criteria

AC-1 Deterministic simulation:
- A local simulation script must show:
  - main fallback `claude -> codex` under throttled state
  - assist behavior non-blocking
  - implementation gate unchanged (`vote + risk` guarded)

AC-2 Workflow syntax:
- All changed shell scripts pass `bash -n`.
- All changed workflow YAML files parse successfully.

AC-3 Live smoke checks:
- `ok` + requested `claude` keeps main as `claude` (unless policy sets codex).
- `degraded/exhausted` + requested `claude` resolves main to `codex` (without force).
- `exhausted` + force keeps `claude`.
- Integrated comments show requested/resolved fields.

AC-4 No system breakage:
- Review-only flow still completes.
- Implement flow gate remains `ok_to_execute == true` and implementation intent required.

## 7. Rollout

1. Ship with assist lane optional and non-blocking.
2. Run smoke rehearsals for throttle states.
3. Keep fallback to codex as safe default.
4. Tighten/expand assist behavior after telemetry confirms stability.
