# Google Workspace Feed Sync Design

## Goal

Periodically extract bounded read-only Google Workspace context and make it
available to `Kernel` and `FUGUE` as cached peripheral evidence.

This design extends the current issue-bound preflight path into a scheduler
path without turning Google Workspace into control-plane truth.

## Core Decision

Do not run a `24/7` daemon.

Use:

- shared scheduled bounded extraction for stable operator rhythms
- personal scheduled mailbox extraction on always-on GitHub Actions
- on-demand preflight for issue-specific context
- TTL-gated feed reuse to avoid repeated API calls and prompt bloat

## Feed Profiles

Source of truth:

- `config/integrations/googleworkspace-feed-policy.json`

Initial profiles:

- `morning-brief-shared`
  - execution target: GitHub Actions
  - environment: `workspace-readonly`
  - actions: `standup-report`
  - ttl: `360m`
  - schedule: weekdays morning
- `morning-brief-personal`
  - execution target: GitHub Actions
  - environment: `workspace-personal-readonly`
  - actions: `gmail-triage`
  - ttl: `360m`
  - schedule: weekdays morning
- `pre-meeting-scan`
  - actions: `meeting-prep`
  - ttl: `45m`
  - default mode: dispatch only
- `weekly-digest-personal`
  - execution target: GitHub Actions
  - environment: `workspace-personal-readonly`
  - actions: `weekly-digest`
  - ttl: `10080m`
  - schedule: weekly

## Feed Artifact Model

Each scheduled extract produces:

- timestamped snapshot under `.fugue/feeds/googleworkspace/<profile>/<snapshot-id>/`
- `latest.json` pointer file under `.fugue/feeds/googleworkspace/<profile>/`
- bounded report and raw adapter outputs inside the snapshot

Canonical manifest fields:

- `profile_id`
- `generated_at`
- `valid_until`
- `ttl_minutes`
- `status`
- `summary`
- `actions`
- `domains`
- `reason`
- `auth_mode`
- `report_path`
- `raw_run_dir`

## Auth Model

Read-only feed sync uses a split auth model:

- service-account credentials for unattended shared calendar/report feeds
- exported user OAuth credentials for unattended personal mailbox feeds

Protected CI secret contract:

- `GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON`
- `GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON`

Environment split:

- `workspace-readonly`
  - protected
  - reviewer-gated
  - shared readonly service-account feeds and issue preflight
- `workspace-personal-readonly`
  - environment-scoped
  - no per-run approval requirement
  - personal readonly mailbox feeds only
  - stores only `GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON`

## Reflection Into Kernel/FUGUE

Reflection happens in two stages:

1. `googleworkspace-scheduled-extract.sh`
   - produces cached feed manifests
2. `googleworkspace-feed-ingest.sh`
   - selects only fresh manifests
   - collapses them into one bounded context JSON
3. `googleworkspace-fetch-feed-artifacts.sh`
   - downloads the latest successful shared and personal feed artifacts when CI
     needs fresh scheduled evidence
4. `resolve-orchestration-context.sh`
   - emits `workspace_feed_status`, `workspace_feed_profiles`, and
     `workspace_feed_summary` for reusable workflows
5. `codex-execute-validate.sh`
   - injects only the combined feed summary into the prompt as peripheral evidence
6. `googleworkspace-personal-feed-sync.yml`
   - runs personal readonly profiles on always-on GitHub Actions
7. `run-local-orchestration.sh`
   - stores `googleworkspace-feed-context.json` beside each local run summary
8. `googleworkspace-feed-sync-local.sh`
   - remains an operator fallback, not the primary scheduler

The sovereign prompt should ingest only the combined summary, not the raw
payloads.

## Safety Rules

- feeds remain peripheral evidence, never task truth
- expired feeds are ignored by default
- scheduled sync remains read-only only
- write adapters are out of scope for feed sync
- schedule frequency should stay low and task-shaped
- shared and personal feeds must remain in separate GitHub Environments
- personal scheduled feeds may use user OAuth refresh tokens only inside the
  dedicated `workspace-personal-readonly` environment

## Simulation Result

The prototype is considered valid if all of these pass:

- fresh feed manifest generation
- TTL cache hit without rerunning preflight
- stale refresh after TTL expiry
- feed ingest only includes fresh manifests
- workflow-target matrix resolution keeps shared and personal feeds separated

This is verified by:

- `tests/test-googleworkspace-scheduled-extract.sh`
- `tests/test-resolve-googleworkspace-feed-matrix.sh`
- `tests/test-googleworkspace-feed-sync-local.sh`
