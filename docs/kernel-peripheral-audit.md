# Kernel Peripheral Audit

## Goal

Validate whether the legacy Claude-side peripherals can survive a transition to a Codex-first `Kernel` without breaking orchestration integrity.

## Current Result

Most peripherals are not inherently Claude-bound at the adapter layer.

- They are primarily `file/CLI/webhook/service` driven.
- Claude coupling exists mainly in orchestration history, skill-native workflows, and selected execution paths.
- This supports a `Codex control plane + Claude executor` architecture.

For Cursorvers-operated systems, the stronger constraint is not model compatibility but interface preservation.

- `Cursorvers` production routes should be treated as protected business interfaces.
- Kernel must integrate with those routes without collapsing them into a single repo or worker prematurely.

## Inventory

| Integration | Primary surfaces | Dependency class | Kernel implication |
|---|---|---|---|
| `auto-video` | `scripts/local/integrations/auto-video.sh`, `/Users/masayuki/Dev/telop-pack-srt-02` | local project dependent | Keep as budgeted peripheral worker |
| `note-semi-auto` | `scripts/local/integrations/note-semi-auto.sh`, `/Users/masayuki/note-manuscript` | Codex-neutral | Safe to keep under Kernel bus |
| `obsidian-audio-ai` | `scripts/local/integrations/obsidian-audio-ai.sh`, Obsidian vault + transcriber | local workflow dependent | Safe under Kernel with optional Claude execution |
| `discord-notify` | local notify adapter + Workers handlers | service dependent | Codex-neutral notification lane |
| `line-notify` | local notify adapter + Workers schema surfaces | service dependent | Codex-neutral notification lane |
| `slide` | Cloudflare slide services + `~/.codex/skills/slide` | external-service dependent | Keep as specialist workflow, Claude optional |
| `supabase` | Workers services + REST bridge | external-service dependent | Codex-neutral, CI-friendly after bridge fixes |
| `stripe` | Workers handlers + REST bridge | external-service dependent | Codex-neutral, CI-friendly after bridge fixes |
| `limitless` | Workers handlers/services | external-service dependent | Outside core Kernel, but compatible as linked external service |

## Cursorvers Contract Map

### Discord

- `workers-hub` already provides verified Discord ingress and outbound notification logic.
- `fugue-orchestrator` provides local outbound notify adapters.
- This is a compatible split for Kernel:
  - ingress/auth at Cloudflare
  - local orchestration notifications at linked-system layer

### LINE

- `workers-hub` does not currently own LINE ingress.
- The active Cursorvers LINE business flow lives in:
  - `/Users/masayuki/Dev/cursorvers_line_free_dev`
- That repo owns:
  - `line-webhook`
  - `line-register`
  - `line-daily-brief`
  - Stripe-to-Discord membership bridge

Kernel implication:

- LINE should be modeled as a cross-repo protected interface, not duplicated into `workers-hub`.
- Kernel should orchestrate around the existing LINE platform rather than absorb it during the first migration.

## Smoke Validation

### Adapter-level smoke

- `note-semi-auto`: pass
- `obsidian-audio-ai`: pass
- `discord-notify`: pass via safe skip when webhook missing
- `line-notify`: pass via safe skip when config missing
- `auto-video`: adapter contract is valid, but its real smoke path is materially heavier than the rest

### Linked-systems end-to-end smoke

Validated with a mocked `gh issue view` provider:

- selected systems: `5`
- success: `5`
- error: `0`
- run dir:
  - `/Users/masayuki/Dev/tmp/kernel-linked-smoke/linked-issue-123-20260306-092737-43141`

This confirms the linked-system bus can run independently of GitHub network state when provided with a stable issue contract.

### Cloudflare Discord regression checks

Validated in `/Users/masayuki/Dev/cloudflare-workers-hub-deploy`:

- `src/handlers/discord.test.ts`
- `src/durable-objects/system-events.test.ts`
- `src/services/notification-service.test.ts`
- `src/services/reflection-notifier.test.ts`

Current result after one implementation fix:

- `129/129` tests passed

### Cursorvers LINE repo validation

Repository:

- `/Users/masayuki/Dev/cursorvers_line_free_dev`

Current result after repair:

- Architectural contract is clear and production-relevant.
- Root-level Deno reproducibility has been repaired with repo-level configuration.
- Focused LINE webhook suite:
  - `deno test supabase/functions/line-webhook/test/ --allow-env --allow-net`
  - result: `68 passed`, `0 failed`, `2 ignored`
- Full functions suite:
  - `deno task test:functions`
  - result: `506 passed`, `0 failed`, `2 ignored`

Kernel implication:

- Kernel can now validate Cursorvers LINE from repo root without ad hoc setup.
- LINE should still remain a protected cross-repo interface in the first Kernel migration.

## Kernel Verification Harness

Cross-repo verification is now wired through:

- `scripts/sim-kernel-peripherals.sh`
- `scripts/check-peripheral-adapters.sh`

Current coverage:

- linked-system integrity
- peripheral adapter contract integrity
- orchestrator topology simulation
- linked-system end-to-end smoke with mocked issue provider
- Cloudflare Discord regression checks
- Cursorvers LINE full functions suite
- static contract probes for Supabase, Vercel, LINE, and Cursorvers business surfaces

## Defects And Readiness Notes

1. `mcp-rest-bridge` smoke had invalid JSON assembly on fallback paths.
2. `sim-orchestrator-switch` depended on current working directory rather than script-relative paths.
3. `auto-video` verification cost is too high for default always-on PDCA loops.
4. `gpt-5.4` is still blocked by model normalization in current policy code.
5. Cross-repo peripheral verification was previously manual and is now promoted into a dedicated Kernel harness.

## Kernel Design Implications

1. Kernel should treat peripherals as `artifact-producing adapters`, not as orchestration authorities.
2. Every adapter needs a cheap `smoke` path before it is admitted to the default verification loop.
3. Heavy adapters should run on a `budgeted verify` policy.
4. Claude should remain available for workflows where the value is in the native execution environment, not in state ownership.
5. Cursorvers-operated production systems must be integrated as protected contracts, even when they live in separate repos or runtimes.
6. Peripherals should use the same explicit adapter vocabulary as sovereign orchestrators: authority, validation mode, contract owner, and preferred lane.
