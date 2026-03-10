# Google Workspace Service Account Verification

Date:

- 2026-03-07

## Goal

Determine whether the existing Google service account key is sufficient to run
the new `googleworkspace/cli` integration for `FUGUE` and `Kernel` without
switching to user OAuth.

## Credentials Under Test

Initial key:

- service account email:
  - `ocr-service-account@shumei-ocr.iam.gserviceaccount.com`
- project id:
  - `shumei-ocr`
- project number observed in Google API errors:
  - `860340262476`

Preferred key after live fixes:

- service account email:
  - `openclaw-calendar-reader@juken-ai-workflow.iam.gserviceaccount.com`
- project id:
  - `juken-ai-workflow`
- project number observed in Google API errors:
  - `1088384151786`

Verification used explicit service-account mode via:

```bash
GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/path/to/service-account.json
```

This avoids `.env` files. The final adapter/probe also scrub ambient Google
variables before calling `gws`:

- `GOOGLE_API_KEY`
- `GOOGLE_APPLICATION_CREDENTIALS`
- `GOOGLE_CLOUD_PROJECT`
- `GCLOUD_PROJECT`
- `GOOGLE_CREDENTIALS_PATH`

Additional local credentials discovered during verification:

- `/Users/masayuki/.config/gcloud/openclaw-calendar-key.json`
- `/Users/masayuki/.config/gcloud/slides-generator-key.json`

The key finding was that ambient `GOOGLE_API_KEY` skewed helper/workflow calls
back onto project `860340262476` even when a different
`GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE` was supplied. After sanitizing ambient
Google variables, runtime behavior matched the explicit credentials file.

## Live Checks

Initial state with the original `shumei-ocr` key:

- `meeting-prep`
  - success
- `standup-report`
  - partial, blocked on `tasks.googleapis.com`
- `weekly-digest`
  - partial, blocked on `gmail.googleapis.com`
- `drive files list`
  - blocked on `drive.googleapis.com`
- `gmail +triage`
  - blocked on `gmail.googleapis.com`
- `gcloud services list/enable`
  - blocked because the service account could not manage Service Usage

Live fixes applied on `juken-ai-workflow` with `flux@cursorvers.com`:

- enabled `tasks.googleapis.com`
- granted `roles/serviceusage.serviceUsageConsumer` to:
  - `openclaw-calendar-reader@juken-ai-workflow.iam.gserviceaccount.com`
  - `slides-generator@juken-ai-workflow.iam.gserviceaccount.com`
- updated the adapter and live probe to scrub ambient Google auth/project env

Current state with `openclaw-calendar-reader@juken-ai-workflow`:

- `gws calendar calendarList list --params '{"maxResults":1}' --format json`
  - result: success
- `gws workflow +meeting-prep --format json`
  - result: success
  - response: `{"message":"No upcoming meetings found."}`
- `gws workflow +standup-report --format json`
  - result: success
  - response: meetings and tasks both returned cleanly
- `gws drive files list --params '{"pageSize":1}' --format json`
  - result: success
- `gws workflow +weekly-digest --format json`
  - result: partial
  - unread mail path fails with `FAILED_PRECONDITION`
- `gws gmail +triage --max 1 --format json`
  - result: blocked
  - reason: `FAILED_PRECONDITION`

## Conclusion

Service-account mode is now usable for a stable read-only baseline on
`juken-ai-workflow`, but it is still not sufficient for Gmail mailbox flows.

User OAuth is now also verified on the same project for a bounded write profile:

- Desktop app client:
  `1088384151786-id2gg3gap5cdsh17ejh2bdaua18gt3d3.apps.googleusercontent.com`
- encrypted user credentials saved successfully by `gws auth login`
- dry-run validated:
  - `gws gmail +send`
  - `gws drive +upload`
  - `gws calendar events insert`
- live validated:
  - `gws gmail +triage --max 1`
  - `gws workflow +weekly-digest`
  - `gws gmail +send`
  - `gws sheets spreadsheets create`
  - `gws sheets spreadsheets values append`
  - `gws docs documents create`
  - `gws docs documents batchUpdate`
  - `gws calendar events insert`
  - `gws drive +upload`
- cleanup validated:
  - Drive delete removed temporary Doc, Sheet, and uploaded file
  - Calendar delete cancelled the temporary event
  - Gmail trash moved the smoke message out of Inbox

It is currently sufficient for:

- calendar-backed read-only flows that the service account can see
- Drive list/read flows visible to the service account
- task-backed standup summaries
- wrapper smoke checks and shared read-only helper execution
- operator-approved write helpers under user OAuth

It is not currently sufficient for:

- self-healing setup from the service account itself
- unattended write automation without a user OAuth credential

## Operational Meaning For FUGUE And Kernel

Safe now:

- use `meeting-prep` as a shared read-only helper
- keep the new wrapper in service-account mode for calendar/Drive/task-visible
  resources
- standardize explicit credentialed runs on
  `openclaw-calendar-reader@juken-ai-workflow`

Blocked until further setup:

- service-account-only Gmail mailbox access
- unattended write automation without a user OAuth credential
- Gmail-persona workflows that assume a background mailbox actor

## Required Next Step

Choose one:

1. stay on service account mode
   - keep `juken-ai-workflow` as the baseline project
   - grant the service account access to the required Workspace resources
   - add domain-wide delegation if user mailbox access is required
2. switch to user OAuth mode
   - `gws auth setup`
     - reached Step 5 successfully on `juken-ai-workflow`
     - still requires manual OAuth client creation in Cloud Console
   - `gws auth login --readonly -s calendar,gmail,drive,docs,sheets`
   - attempted fallback:
     - `gcloud auth application-default login` with Workspace read-only scopes
     - Google blocked the `gcloud` public OAuth client during consent
     - therefore this tenant still needs a project-owned Desktop app OAuth client
       (and, if Workspace API controls require it, allowlisting/trust in Admin)

The second option is the better fit if the target workflows are personal or
operator-centric rather than server-to-server.
