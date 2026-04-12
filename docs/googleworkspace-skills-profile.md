# Google Workspace Skills Profile

This profile defines a curated `googleworkspace/cli` skill set for both `FUGUE`
and `Kernel`.

## Goals

- Keep Google Workspace operations usable from both Codex and Claude paths.
- Prefer `SKILL.md + gws CLI` over `gws mcp` for routine operator workflows.
- Keep Workspace activity outside the control plane: evidence and side effects
  may happen in Workspace, but orchestration truth remains in FUGUE or Kernel.

## Default Operating Model

Use Google Workspace through:

1. installed `gws-*` skills
2. the `gws` CLI
3. bounded command output (`--format table` or narrow `json`)

Do **not** make `gws mcp` the default path for FUGUE or Kernel. MCP remains an
optional compatibility route for clients that can only consume MCP tools.

Why:

- `SKILL.md` is loaded on demand and stays small.
- CLI output can be intentionally bounded by command shape and format flags.
- MCP tool catalogs and large tool responses tend to widen the active context
  surface faster than focused CLI calls.
- `gws` already ships task-shaped helper skills and workflows, which reduces the
  need for a schema-heavy MCP path in daily use.

## Baseline Source Of Truth

Manifest:

- `config/skills/googleworkspace-cli-baseline.tsv`

Sync script:

- `scripts/skills/sync-googleworkspace-skills.sh`

Upstream:

- `https://github.com/googleworkspace/cli`

The sync script pins upstream to commit
`95bb24e9c2d5dd165fb0b3c81ad82a42ad31fc3f` by default.

## Selected Skills

Required profile:

- `gws-shared`
- `gws-gmail`
- `gws-gmail-triage`
- `gws-calendar`
- `gws-drive`
- `gws-docs`
- `gws-sheets`
- `gws-workflow`
- `gws-workflow-meeting-prep`
- `gws-workflow-standup-report`
- `gws-workflow-weekly-digest`

Optional profile (`--with-optional`):

- write helpers such as `gws-gmail-send`, `gws-drive-upload`, `gws-docs-write`
- focused helpers such as `gws-sheets-read`, `gws-sheets-append`
- workflow extensions such as `gws-workflow-email-to-task`,
  `gws-workflow-file-announce`
- role/task guidance such as `persona-exec-assistant`,
  `recipe-generate-report-from-sheet`

## Install Examples

Install the CLI:

```bash
npm install -g @googleworkspace/cli
```

Sync required skills into both orchestrator homes:

```bash
./scripts/skills/sync-googleworkspace-skills.sh --target both
```

Include optional skills:

```bash
./scripts/skills/sync-googleworkspace-skills.sh --target both --with-optional
```

Dry-run preview:

```bash
./scripts/skills/sync-googleworkspace-skills.sh --target both --with-optional --dry-run
```

## Authentication

Preferred interactive setup:

```bash
gws auth setup
gws auth login
```

Observed on `2026-03-07`:

- `gws auth setup` successfully advanced through project/API setup on
  `juken-ai-workflow`
- final completion still required a manual Cloud Console step to create a
  `Desktop app` OAuth client and save it as
  `~/.config/gws/client_secret.json`
- until that file exists, `gws auth login` returns `No OAuth client configured`
- `gcloud auth application-default login` with Workspace read-only scopes was
  also tested, but Google blocked the public `gcloud` OAuth client for this
  consent flow, so ADC is not a complete replacement here

If `gcloud` is unavailable or project creation must stay manual, keep auth
outside FUGUE/Kernel automation and authenticate the operator terminal first.

Service-account mode is also supported when `.env` files are not allowed:

```bash
./scripts/lib/googleworkspace-cli-adapter.sh \
  --credentials-file /secure/path/service-account.json \
  --action meeting-prep
```

Verified baseline service-account path:

- project: `juken-ai-workflow`
- service account:
  `openclaw-calendar-reader@juken-ai-workflow.iam.gserviceaccount.com`
- verified actions:
  - `meeting-prep`
  - `standup-report`
  - `drive files list`
- wrapper behavior:
  - scrubs ambient `GOOGLE_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`,
    `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`, and `GOOGLE_CREDENTIALS_PATH`
    whenever `--credentials-file` is used
- known service-account limitation:
  - Gmail mailbox helpers such as `gmail-triage` still require user OAuth or
    domain-wide delegation

Verified user OAuth write path:

- Desktop app client installed at `~/.config/gws/client_secret.json`
- encrypted user credentials stored at `~/.config/gws/credentials.enc`
- verified write-capable scopes:
  - `https://www.googleapis.com/auth/drive`
  - `https://www.googleapis.com/auth/spreadsheets`
  - `https://www.googleapis.com/auth/gmail.modify`
  - `https://www.googleapis.com/auth/calendar`
  - `https://www.googleapis.com/auth/documents`
- dry-run validated actions:
  - `gws gmail +send`
  - `gws drive +upload`
  - `gws calendar events insert`
- live validated adapter actions:
  - `gmail-triage`
  - `weekly-digest`
  - `gmail-send --dry-run`
  - `docs-create`
  - `docs-insert-text`
  - `sheets-create`
  - `sheets-append`
  - `calendar-insert`
  - `drive-upload`
- cleanup verified:
  - temporary Doc, Sheet, uploaded Drive file removed
  - temporary Calendar event cancelled
  - temporary Gmail smoke message moved to Trash

Current repo-side live verification:

- `docs/googleworkspace-service-account-verification-2026-03-07.md`
- `scripts/check-googleworkspace-live.sh`

Current repo-side Kernel integration helpers:

- `scripts/lib/orchestrator-nl-hints.sh`
  - now emits `workspace_action_hint`, `workspace_domain_hint`,
    `workspace_reason`, and `workspace_hint_applied`
- `scripts/harness/resolve-orchestration-context.sh`
  - now exports Workspace route hints to `GITHUB_OUTPUT`
  - includes `workspace_suggested_phases`,
    `workspace_readonly_actions`, and
    `workspace_approval_required_actions`
- `scripts/lib/googleworkspace-cli-adapter.sh`
  - supports `--run-dir` evidence output
  - supports `--ok-to-execute` and `--human-approved` write gating
- `scripts/local/run-local-orchestration.sh`
  - writes `googleworkspace-context.json` into each run directory
- `scripts/harness/googleworkspace-preflight-enrich.sh`
  - produces a bounded readonly Workspace artifact for CI preflight
  - degrades to `skipped` when no Workspace credentials are available
- `scripts/harness/googleworkspace-scheduled-extract.sh`
  - generates TTL-bound readonly Workspace feed manifests for scheduled use
- `scripts/harness/googleworkspace-feed-ingest.sh`
  - collapses only fresh feed manifests into one bounded context artifact

## CI Secret Contract

Readonly GitHub Actions preflight uses a protected `Environment` secret rather
than a repo-level secret.

Recommended environment:

- `workspace-readonly`
  - configure required reviewers or approval rules
  - expose `GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON` only in this environment
- `workspace-personal-readonly`
  - environment-scoped, no per-run reviewer gate
  - expose `GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON` for personal mailbox feeds

Secret:

- `GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON`
  - service-account JSON payload
  - intended only for readonly preflight actions
  - consumed by `scripts/harness/googleworkspace-preflight-enrich.sh`
  - not passed through the caller workflow as a reusable-workflow secret
- `GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON`
  - optional `authorized_user` JSON payload for mailbox helpers such as
    `gmail-triage` and `weekly-digest`
  - generate it with:
    ```bash
    gws auth export --unmasked > credentials.json
    ```
  - note: masked `gws auth export` output is not valid for CI use
  - consumed only inside the protected readonly preflight job

Protection model:

- first guard: readonly service-account scope only
- second guard: protected `Environment` approval before the preflight job can
  read the secret
- scheduled personal mailbox feeds use a separate environment-scoped secret and
  do not share the protected approval path used by issue preflight
- shared scheduled feeds receive only the service-account secret
- personal scheduled feeds receive only the user OAuth export secret
- mailbox helpers prefer `GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON` when present
  and otherwise degrade gracefully under service-account mode

If the environment secret is absent, the CI workflow does not fail. It emits a
`skipped` Workspace artifact instead and continues with the normal Codex path.

Current CI path:

- caller forwards `workspace_*` hints into `fugue-codex-implement`
- reusable workflow routes Workspace preflight into a dedicated protected job
- the protected job reads secrets only from `workspace-readonly`
- implementation job downloads the preflight artifact and does not receive the
  Workspace credential secret directly
- manual smoke entrypoint:
  - `.github/workflows/googleworkspace-readonly-smoke.yml`
  - use this when protected readonly Workspace verification is needed without
    going through Tutti execution approval
- readonly preflight artifact lands at:
  - `.fugue/pre-implement/issue-<n>-googleworkspace.md`
- raw readonly evidence lands at:
  - `.fugue/pre-implement/googleworkspace-run/googleworkspace/`
- scheduled feed sync prototype:
  - `scripts/harness/googleworkspace-fetch-feed-artifacts.sh`
  - `config/integrations/googleworkspace-feed-policy.json`
  - `scripts/harness/resolve-googleworkspace-feed-matrix.sh`
  - `scripts/harness/googleworkspace-scheduled-extract.sh`
  - `scripts/harness/googleworkspace-feed-ingest.sh`
  - `.github/workflows/googleworkspace-feed-sync.yml`
  - `.github/workflows/googleworkspace-personal-feed-sync.yml`
  - `scripts/local/googleworkspace-feed-sync-local.sh`
  - `scripts/harness/resolve-orchestration-context.sh` can fetch the latest
    feed artifacts and emit `workspace_feed_*` outputs
  - `scripts/harness/codex-execute-validate.sh` injects only feed summaries,
    never raw payloads, into Codex execution prompts
  - `scripts/local/run-local-orchestration.sh` writes
    `googleworkspace-feed-context.json` into each run directory
  - `fugue-status` reports the latest feed workflow runs in status comments

## Safety Rules

- Read `gws-shared` before using any Workspace write helper.
- Use `--dry-run` on write/delete-capable commands when available.
- Prefer read-only workflows such as `gws workflow +meeting-prep`,
  `gws gmail +triage --max 10`, and `gws workflow +weekly-digest` for routine
  operator assistance.
- In service-account mode, treat Gmail helpers as opt-in only. The verified
  baseline for FUGUE/Kernel is Calendar + Drive + Tasks read-only.
- Use the write adapter only with explicit human approval. The verified
  write-capable baseline is Gmail send, Drive upload, and Calendar insert.
- Treat generated Docs, Sheets, or Drive writes as peripheral side effects, not
  control-plane truth.
- When `--run-dir` is provided, persist raw output plus a `*-meta.json` receipt
  under `<run-dir>/googleworkspace/`.

## FUGUE And Kernel Fit

`FUGUE` fit:

- next-meeting preparation
- standup/reporting support
- Drive/Docs/Sheets artifact support around issue work
- Gmail-aware flows only after user OAuth or domain-wide delegation
- operator-approved write actions via the write adapter

`Kernel` fit:

- bounded peripheral skill family under the execution or adapter plane
- no change to sovereign routing or execution approval
- evidence-producing workflow, not governance logic
- shared read-only adapter: `googleworkspace-cli-readonly`
- shared write adapter: `googleworkspace-cli-write`
- operating design:
  - `docs/kernel-googleworkspace-integration-design.md`
  - `config/integrations/googleworkspace-kernel-policy.json`

Example adapter usage:

```bash
./scripts/lib/googleworkspace-cli-adapter.sh --action meeting-prep --resolve-only
./scripts/lib/googleworkspace-cli-adapter.sh --action gmail-triage --max 10
./scripts/lib/googleworkspace-cli-adapter.sh --action gmail-send --to flux@cursorvers.com --subject "Test" --body "Hello" --dry-run
./scripts/lib/googleworkspace-cli-adapter.sh --action drive-upload --file ./README.md --dry-run
./scripts/lib/googleworkspace-cli-adapter.sh --action calendar-insert --calendar primary --event-json '{"summary":"Test","start":{"dateTime":"2026-03-08T10:00:00+09:00"},"end":{"dateTime":"2026-03-08T10:30:00+09:00"}}' --dry-run
./scripts/lib/googleworkspace-cli-adapter.sh --action docs-create --title "Test Doc" --format json
./scripts/lib/googleworkspace-cli-adapter.sh --action docs-insert-text --document-id DOC_ID --text "Hello" --format json
./scripts/lib/googleworkspace-cli-adapter.sh --action sheets-create --title "Test Sheet" --format json
./scripts/lib/googleworkspace-cli-adapter.sh --action sheets-append --spreadsheet-id SHEET_ID --range 'シート1!A1' --values-json '{"values":[["a","b"]]}' --format json
```

## Adjacent CLI-First Candidates

Current repo evidence suggests these MCP surfaces are better managed with
`skills + CLI` style wrappers than as default MCP-first integrations:

- `supabase-rest-mcp`
  - already deterministic CLI/REST bridge logic via
    `scripts/lib/mcp-rest-bridge.sh`
- `stripe-rest-mcp`
  - same deterministic REST bridge pattern as Supabase

Keep MCP-first for now:

- `pencil-session-mcp`
- `excalidraw-session-mcp`
- `slack-session-mcp`
- `vercel-session-mcp`

These still carry session/runtime coupling that is not improved by forcing them
into a fake CLI-only shape.
