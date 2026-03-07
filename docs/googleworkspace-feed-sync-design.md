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
- local personal mailbox extraction for user-owned context
- on-demand preflight for issue-specific context
- TTL-gated feed reuse to avoid repeated API calls and prompt bloat

## Feed Profiles

Source of truth:

- `config/integrations/googleworkspace-feed-policy.json`

Initial profiles:

- `morning-brief-shared`
  - execution target: GitHub Actions
  - actions: `standup-report`
  - ttl: `360m`
  - schedule: weekdays morning
- `morning-brief-personal`
  - execution target: local machine
  - actions: `gmail-triage`
  - ttl: `360m`
  - schedule: weekdays local morning
- `pre-meeting-scan`
  - actions: `meeting-prep`
  - ttl: `45m`
  - default mode: dispatch only
- `weekly-digest-personal`
  - execution target: local machine
  - actions: `weekly-digest`
  - ttl: `10080m`
  - schedule: weekly local

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
- local encrypted `gws auth login` credentials for personal mailbox feeds

Protected CI secret contract for shared feeds:

- `GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON`

Personal mailbox feeds should run locally and should not require GitHub Actions
to store long-lived user refresh tokens for unattended schedule execution.

## Reflection Into Kernel/FUGUE

Reflection happens in two stages:

1. `googleworkspace-scheduled-extract.sh`
   - produces cached feed manifests
2. `googleworkspace-feed-ingest.sh`
   - selects only fresh manifests
   - collapses them into one bounded context JSON
3. `googleworkspace-feed-sync-local.sh`
   - runs local-only profiles with user OAuth on the operator machine

The sovereign prompt should ingest only the combined summary, not the raw
payloads.

## Safety Rules

- feeds remain peripheral evidence, never task truth
- expired feeds are ignored by default
- scheduled sync remains read-only only
- write adapters are out of scope for feed sync
- schedule frequency should stay low and task-shaped
- unattended GitHub Actions schedule should not depend on user OAuth refresh
  tokens

## Simulation Result

The prototype is considered valid if all of these pass:

- fresh feed manifest generation
- TTL cache hit without rerunning preflight
- stale refresh after TTL expiry
- feed ingest only includes fresh manifests

This is verified by:

- `tests/test-googleworkspace-scheduled-extract.sh`
- `tests/test-googleworkspace-feed-sync-local.sh`
