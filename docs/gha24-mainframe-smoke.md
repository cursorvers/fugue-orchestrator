# GHA24 Mainframe Smoke Flow

## Purpose
Outline how the new GHA24 smoke workflow exercises the "mainframe" stage of the FUGUE pipeline, ensuring the nightly scenario/script handoff to the mainframe bridge is still healthy before larger assets are generated.

## Scope
- Phase 1-2 artifacts (scenario.json / script.json) produced by Claude/Codex stay immutable once sent to the bridge.
- Phase 3-4 execution happens on the on-prem/mainframe-like execution host that exposes a submitted job, spool files, and a binary success flag.
- Smoke coverage is limited to the control path: submission, completion, artifact download, and threshold checks.

## Flow steps
1. **Trigger**: `fugue-task-router.yml` sees an open GHA24 issue tagged `mainframe-smoke` (or an automated schedule). The issue body drives the scenario metadata and deploys the `tutti` vote if needed.
2. **Preparation**: Claude/Codex agents generate the required `scenario.json`, `script.json`, and metadata, storing them as GitHub Artifacts (naming convention `gha24-scenario-${RUN_ID}.zip`). The artifact includes a `manifest.json` with dataset hashes and mainframe job instructions.
3. **Bridge upload**: `fugue-mainframe-smoke` (orchestrated by the new `mainframe-smoke` workflow) downloads the artifact, decrypts secrets from `secrets-management.md`, and posts the payload to the mainframe bridge API (`/api/submit-smoke`). The bridge returns a job token and estimated completion window (~3 minutes).
4. **Health polling**: The workflow polls the bridge for stdout/stderr dumps and a final `exit_code`. Smoke success requires `exit_code == 0`, the presence of `script.json` (`artifact/script.json`), and the derived runtime logs (e.g., 4 snippets at least 80 words each) in the spool.
5. **Artifact collection**: Successful smoke runs push a zipped bundle (`mainframe-smoke-results.tar.gz`) back into GitHub Artifacts, including:
   - `spool.log` (with the raw mainframe log)
   - `delta.json` (summary of what the mainframe did vs. expectations)
   - `final-script.json` (hardened script after mainframe validation)
6. **Report**: The workflow climbs the `fugue-watchdog`/Discord alert path if any check fails and leaves a short summary comment on the originating GHA24 issue so the Codex team can follow up.

## Smoke assertions
- Artifact integrity: `manifest.json` hash matches `scenario.json`/`script.json`; zipped payload is not empty.
- Timeliness: The bridge must report `exit_code` within 5 minutes; otherwise the job is considered stalled and triggers a retry.
- Output completeness: At least one `final-script.json` frame, 2+ log segments, and `exit_code == 0` are required to mark the run `success`.
- Health metrics: Bridge response times must stay < 2s per poll; poll backoff is 15s after the third attempt to avoid flooding.
- Governance: Failed runs automatically queue a new `fugue-task-router` invocation and notify the Discord channel via `fugue-watchdog`.

## Observability & escalation
- Logs stream to Actions; the `smoke` workflow sets `LOG_LEVEL=debug` to keep job IDs in the trace output.
- `fugue-watchdog` monitors the workflow run rate: if no successful `mainframe-smoke` run exists within 6 hours, the controller posts a Discord alert with the last success timestamp.
- `tutti` votes tied to the issue summarize the `manifest` + `delta.json` so the governance layer can inspect mismatches quickly.

## Next steps
1. Keep the `mainframe-smoke` workflow in sync with the `secrets-management` guidance (rotate bridge keys quarterly).
2. Expand the smoke bundle with a `metrics.json` payload once the mainframe exposes per-operator latencies.
3. Automate rerun policies so that a failed smoke run re-queues itself once, then escalates to the human-in-the-loop team if it still fails.
