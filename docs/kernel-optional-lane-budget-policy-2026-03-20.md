# Kernel Optional Lane Budget Policy (2026-03-20)

## Goal

Use free-tier or quota-limited optional specialists aggressively enough to preserve multi-model diversity,
but conservatively enough that `Kernel` does not burn through scarce allowances and silently collapse back
to `codex`-only operation.

This policy separates:

- `official hard limit`: vendor-published quota or plan statement
- `internal soft budget`: the ceiling `Kernel` should target in normal operation

## Baseline vs Optional

- Normal minimum healthy Kernel shape is `codex + glm + one specialist`.
- `codex` is non-replaceable because it is the sovereign orchestrator.
- `gemini-cli`, `cursor-cli`, and `copilot-cli` are specialist voices with quota-aware routing.
- If `glm` fails twice in the same run, `Kernel` may enter `degraded-allowed` and continue as `codex + specialist + specialist`.
- If no valid three-voice shape is available, `Kernel` must fail closed rather than claim healthy multi-model orchestration.

## Official Limits

### `gemini-cli`

- Official source: Google's `google-gemini/gemini-cli` README.
- With personal Google account OAuth:
  - `60 requests/minute`
  - `1,000 requests/day`
- With Gemini API key free tier:
  - `100 requests/day` for `Gemini 2.5 Pro`

### `copilot-cli`

- Official source: GitHub Docs.
- `GitHub Copilot Free` includes:
  - `50 premium requests/month`
  - `2,000 inline suggestion requests/month`
- All chat interactions count as premium requests.
- In autopilot mode, additional continuation steps also consume premium requests, and model multipliers can increase cost.

### `cursor-cli`

- Official source: Cursor pricing/usage docs.
- `Hobby` is documented only as including `limited Agent requests`.
- Cursor's public docs do not publish an exact numeric Hobby quota.
- Cursor instructs users to monitor usage via the dashboard and editor limit notifications.

## Kernel Internal Soft Budgets

These are policy choices, not vendor promises.

### `gemini-cli`

- Role: default optional specialist
- Use for:
  - UI/UX critique
  - second-opinion review
  - fast external dissent lane
  - visual or product-language challenge
- Internal soft budget:
  - `<= 200 requests/day`
  - `<= 20 requests/run`
- Rationale:
  - published free ceiling is high enough to make Gemini the primary optional lane
  - keep substantial headroom below the official `1,000/day` ceiling

### `cursor-cli`

- Role: secondary optional specialist
- Use for:
  - agent-style alternate implementation critique
  - terminal-native second opinion
  - occasional integration or synthesis challenge
- Internal soft budget:
  - `<= 20 requests/month`
  - `<= 1 request/run`
- Rationale:
  - official Hobby exact quota is unpublished
  - `Kernel` must assume the free pool is scarce until proven otherwise
  - stop immediately on any dashboard or in-editor usage warning

### `copilot-cli`

- Role: scarce dissent or final-check specialist
- Use for:
  - one-shot counterproposal
  - final pre-merge dissent
  - compact review challenge
- Internal soft budget:
  - `<= 12 premium requests/month`
  - `<= 1 premium request/run`
- Rationale:
  - official free allowance is only `50 premium requests/month`
  - autopilot can spend multiple premium requests per task
  - preserve most of the monthly quota for high-value disagreements, not routine execution

## Routing Rules

### Small tasks

- Optional specialists are skipped by default.
- Exception:
  - one `gemini-cli` lane is allowed for UI/UX or wording-sensitive tasks.

### Medium tasks

- Prefer exactly one optional specialist lane.
- Selection order:
  1. `gemini-cli`
  2. `cursor-cli`
  3. `copilot-cli`

### Large or high-risk tasks

- Allow up to two optional specialist lanes when budgets permit.
- Selection order:
  1. `gemini-cli`
  2. `cursor-cli`
- `copilot-cli` is reserved for final dissent or explicit tie-break review.

## Hard Constraints

- `copilot-cli` must not run in autopilot mode on a free plan by default.
- `copilot-cli` must be one-shot only unless a human explicitly overrides policy.
- `cursor-cli` must be treated as dashboard-governed, not quota-guaranteed.
- `gemini-cli` is the only optional lane that may be considered routine.
- Optional-lane exhaustion must degrade to:
  - `gemini-cli` exhausted -> skip Gemini, continue with baseline quorum
  - `cursor-cli` warning/limit -> disable Cursor for the rest of the period
  - `copilot-cli` budget exhausted -> disable Copilot until next monthly reset

## Operator Guidance

- Review quotas weekly, not ad hoc.
- Prefer wrapper commands:
  - `kgemini`
  - `kcursor`
  - `kcopilot`
- These wrappers enforce `budget-can-use` before execution and `budget-record` after execution.
- Prefer a stable run id via `KERNEL_RUN_ID` or tmux session name so doctor, budget, and glm state all point to the same run.
- If `cursor-cli` publishes exact Hobby limits later, replace the conservative soft cap with a documented hard/soft pair.
- If `copilot-cli` is upgraded from Free, revisit the soft cap and autopilot prohibition.

## Sources

- Gemini CLI README: <https://github.com/google-gemini/gemini-cli>
- Gemini API quota docs: <https://ai.google.dev/gemini-api/docs/quota>
- GitHub Copilot premium requests: <https://docs.github.com/en/copilot/managing-copilot/monitoring-usage-and-entitlements/about-premium-requests>
- GitHub Copilot CLI docs: <https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli-agents/overview>
- Cursor pricing / usage docs: <https://docs.cursor.com/account/rate-limits>
