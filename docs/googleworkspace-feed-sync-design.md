# Google Workspace Feed Sync Design

## Goal

Periodically extract bounded read-only Google Workspace context and make it
available to `Kernel` and `FUGUE` as cached peripheral evidence.

This design extends the current issue-bound preflight path into a scheduler
path without turning Google Workspace into control-plane truth.

## Core Decision

Do not run a `24/7` daemon.

Use:

- scheduled bounded extraction for stable operator rhythms
- on-demand preflight for issue-specific context
- TTL-gated feed reuse to avoid repeated API calls and prompt bloat

## Feed Profiles

Source of truth:

- `config/integrations/googleworkspace-feed-policy.json`

Initial profiles:

- `morning-brief`
  - actions: `standup-report`, `gmail-triage`
  - ttl: `360m`
  - schedule: weekdays morning
- `pre-meeting-scan`
  - actions: `meeting-prep`
  - ttl: `45m`
  - default mode: dispatch only
- `daily-mailbox-digest`
  - actions: `gmail-triage`
  - ttl: `180m`
  - default mode: dispatch only
- `weekly-digest`
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

Read-only feed sync reuses the existing dual auth split:

- service-account credentials for shared calendar/report flows
- optional `authorized_user` export for mailbox helpers

Protected CI secret contract:

- `GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON`
- `GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON`

Mailbox actions prefer the user OAuth export when present and degrade when it
is absent.

## Reflection Into Kernel/FUGUE

Reflection happens in two stages:

1. `googleworkspace-scheduled-extract.sh`
   - produces cached feed manifests
2. `googleworkspace-feed-ingest.sh`
   - selects only fresh manifests
   - collapses them into one bounded context JSON

The sovereign prompt should ingest only the combined summary, not the raw
payloads.

## Safety Rules

- feeds remain peripheral evidence, never task truth
- expired feeds are ignored by default
- scheduled sync remains read-only only
- write adapters are out of scope for feed sync
- schedule frequency should stay low and task-shaped

## Simulation Result

The prototype is considered valid if all of these pass:

- fresh feed manifest generation
- TTL cache hit without rerunning preflight
- stale refresh after TTL expiry
- feed ingest only includes fresh manifests

This is verified by:

- `tests/test-googleworkspace-scheduled-extract.sh`
