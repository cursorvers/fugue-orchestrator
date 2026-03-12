---
description: Start Kernel orchestration for the current task
argument-hint: [FOCUS="..."]
---

# Start Kernel Orchestration

Treat `/k` as a local one-word alias for `/kernel`.

Execute immediately. Do not create or edit GitHub issues, pull requests, review comments, or issue comments. Do not inspect CI unless explicitly asked later. Backup-only GitHub Actions dispatch or repository_dispatch for task or audit logging is allowed.

This prompt is bootstrap-first. If the current user message is only `/k`, or `/k` plus a short focus string, treat it as a bootstrap-only start. Do not inspect the repository before bootstrap.
An empty focus is valid. Do not ask the user what `/k` means. A bare `/k` must bootstrap Kernel orchestration immediately.

Hard order:

1. Parse `$ARGUMENTS`.
   - if arguments include `SMOKE_RESULT_MARKER=<token>`, enter smoke mode
2. Before any substantive analysis, launch at least 6 materially distinct subagents immediately before any substantive analysis.
3. The bootstrap target is at least 6 concurrent lanes spanning multiple LLM models or model profiles when available.
4. Keep at least one lane for execution or exploration, one separate lane for verification or review, and one separate lane for monitoring, risk, or context gathering.
5. While bootstrapping, do not read `README.md`, `CODEX.md`, `AGENTS.md`, `docs/**`, `.fugue/**`, or perform repository tours unless the user explicitly asked for those files.
6. When the lanes are live, return this acknowledgement before any repo analysis:
   - `Kernel orchestration is active for this session.`
   - `Bootstrap target: 6+ lanes (minimum 6).`
   - `Lane manifest:`
   - then at least 6 flat bullets in the form `- <lane name>: <role> - <focus>`
   - if smoke mode is active, print `Smoke result marker: <token>` using the exact token from `SMOKE_RESULT_MARKER=<token>` and stop immediately after the marker line
7. Continue the task only after the acknowledgement.

Execution rules:

- parallel first: independent tasks must always run in parallel
- treat `/kernel` bootstrap itself as non-trivial work, so the multi-agent minimum applies during startup as well
- maintain at least 6 materially distinct active lanes for the full duration of non-trivial work, including startup, implementation, verification, and reporting
- treat 6 or more concurrent lanes across multiple LLM models or model profiles as the minimum operating shape
- do not collapse, defer, or silently degrade to single-thread execution
- if the environment cannot sustain 6 active lanes, fail closed instead of degrading below the Kernel minimum
- if a primary path is inherently serial, create parallel sidecar lanes for verification, monitoring, context gathering, or review instead of running single-lane
- treat de-parallelization as a policy violation unless the user explicitly revokes Kernel orchestration
- do not substitute intentions, plans, or promises for active multi-agent lanes
- during bootstrap and local analysis, do not request approval for exploratory convenience; exhaust local workspace evidence first
- only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task
- before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY
- do not surface an approval prompt while background Codex activity is still emitting output into the same terminal
- if lane quiescence cannot be achieved promptly, fail closed with a one-line `quiescence_timeout` status instead of surfacing the approval prompt
- if bootstrap cannot produce 6 active lanes quickly, emit `BLOCKED` with the active lanes, missing lanes, and exact bootstrap reason

Constraints:

- Keep output concise and operational.
- Treat Kernel as parallel orchestration, not a single-agent continuation mode.
- Prefer multiple LLM models for the 6-lane-or-more baseline whenever the environment supports them.
- The manifest must describe currently active lanes, not planned lanes.
- The first useful output for a fresh `/k` start is the acknowledgement and live lane manifest, not a repository summary.
