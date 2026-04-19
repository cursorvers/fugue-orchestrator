---
name: research-loop
description: Iterative research, hypothesis testing, and optimization loop with bounded evidence gathering.
---

# research-loop

Use this skill when a task asks for an iterative research, hypothesis testing, or optimization loop.

## Contract

1. Restate the working hypothesis, target outcome, and stopping condition.
2. Run bounded evidence gathering from the available local tools or approved sources.
3. Compare the evidence against the hypothesis and record what changed.
4. Propose the next experiment or implementation adjustment.
5. Stop when the requested outcome is reached, the stopping condition is met, or a blocking dependency is explicit.

## Safety

- Do not request user approval for non-critical routine research steps when an approved local tool or read-only source is available.
- Escalate only for destructive actions, credential changes, paid/external side effects, or production-impacting writes.
- Keep artifacts concise and cite local file paths or external sources used.
