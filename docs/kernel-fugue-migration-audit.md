# Kernel FUGUE Migration Audit

## Goal

Audit whether `Kernel` has preserved the essential FUGUE doctrines, whether peripheral compatibility is strong enough for migration, and whether a controlled re-switch back to legacy FUGUE remains possible.

This is a design and validation audit. Runtime control-path evidence is now included, but the document still treats Kernel as an evolving migration target rather than a finished product.

## Verdict

`Kernel` is runtime-capable as the successor to FUGUE, and the validated core plus protected peripherals are now production-ready.

Current state:

- doctrine preservation: `validated`
- peripheral compatibility: `validated by repeated simulation`
- re-switch to legacy FUGUE: `contract-valid, runtime-valid through explicit fugue-bridge handoff`

So the honest assessment is:

- `Kernel` is functionally complete across the validated core and protected peripheral set
- the remaining gaps are concentrated in optional adapter hardening rather than migration-critical behavior

## FUGUE Layers And Kernel Status

| FUGUE layer | Legacy role | Kernel status | Evidence |
|---|---|---|---|
| governance doctrine | multi-model approval, risk gating, evidence-first | preserved | `docs/requirements-gpt54-codex-kernel.md` |
| sovereign control plane | routing, council integration, execution approval | redefined under adapter contract | `docs/kernel-sovereign-adapter-contract.md` |
| lane fabric | 6+ lanes, baseline trio, specialist add-ons | preserved and generalized | `AGENTS.md`, `docs/requirements-gpt54-codex-kernel.md` |
| local linked systems | artifact and notification bus | validated | `config/integrations/local-systems.json`, `scripts/local/run-linked-systems.sh` |
| cross-repo business surfaces | Cloudflare, Cursorvers LINE, Vercel, Supabase | validated as protected adapters | `config/integrations/peripheral-adapters.json` |
| provider reversibility | Claude/Codex switching in legacy FUGUE | formalized as typed adapter set | `config/orchestration/sovereign-adapters.json` |

## Doctrines Preserved

The following FUGUE doctrines are carried into Kernel without dilution:

1. governance-first execution control
2. baseline autonomous write council of `Codex + GLM + specialist`
   - `Claude` remains a recommended extra voice when healthy, not a Kernel prerequisite
3. human approval only for destructive, irreversible, or trust-boundary operations
4. evidence before completion
5. peripherals and business interfaces treated as part of orchestration reality

## Doctrines Intentionally Retired

Kernel intentionally does not preserve these legacy assumptions:

1. the main orchestrator must never execute
2. Claude must be the default sovereign control plane
3. provider-specific throttling should shape the entire architecture

These are replaced by:

1. `gpt-5.4` default sovereignty
2. adaptive task-shape topology
3. explicit sovereign and peripheral adapter contracts

## Peripheral Compatibility

Peripheral compatibility is strong enough for implementation work to proceed.

Validated surfaces:

- linked local systems
- Discord via Cloudflare ingress plus local notify split
- Cursorvers LINE as a protected cross-repo contract
- Supabase and Vercel boundary contracts
- slide and Manus specialist workflows

Production-backed evidence now includes:

- Cloudflare production health and Cockpit auth probes
- GitHub live canary success for Kernel and `fugue-bridge` rollback
- Cursorvers LINE authenticated production `health-check` returning `200 OK`
- latest Cursorvers LINE `Deploy Supabase Edge Functions` run succeeding on the fixed head
- manual Cursorvers LINE `CI Tests` rerun succeeding on the current head
- manual Cursorvers LINE `Manus Audit (Unified)` daily run succeeding after execution/finding separation and GitHub-token soft-fail handling
- Kernel MCP adapter execution harness succeeding for Pencil, Excalidraw, Slack fallback, Vercel, and REST bridge routes

Repeated validation evidence:

- `scripts/sim-kernel-peripherals.sh` passes repeatedly
- linked-system smoke stays green
- Cloudflare Discord regression subset stays green
- Cursorvers LINE function suite stays green

## Re-switch To FUGUE

Re-switch is modeled as an explicit adapter problem, not as a hidden fallback.

Required path:

1. `codex-sovereign` remains the default Kernel owner
2. `claude-sovereign-compat` remains the optional future Claude-main mode
3. `fugue-bridge` is the only supported rollback path to legacy FUGUE

What is already true:

- `fugue-bridge` is named in the requirements
- `fugue-bridge` is represented in the sovereign adapter manifest
- validation checks now require the bridge to remain contract-compatible

What is not yet true:

- every peripheral is already fully Kernel-native
- `claude-sovereign-compat` is promoted beyond contract-level readiness
- Cloudflare/Cockpit naming has fully converged on Kernel terminology

Re-switch status:

- `design-valid`
- `simulation-valid`
- `runtime-valid through explicit bridge dispatch`

## Simulation Coverage

Current verification fabric covers:

1. linked-system integrity
2. sovereign adapter contract integrity
3. sovereign adapter switch simulation
4. peripheral adapter contract integrity
5. MCP adapter execution paths
6. orchestration matrix simulation
7. linked-system smoke with mocked issue provider
8. Cloudflare Discord regression subset
9. Cursorvers LINE function suite
10. static contract probes for protected interfaces

Primary entry points:

- `scripts/check-linked-systems-integrity.sh`
- `scripts/check-sovereign-adapters.sh`
- `scripts/sim-sovereign-adapter-switch.sh`
- `scripts/check-peripheral-adapters.sh`
- `tests/test-mcp-adapter-exec.sh`
- `scripts/sim-orchestrator-switch.sh`
- `scripts/sim-kernel-peripherals.sh`

## Remaining Gaps

The remaining gaps are concrete:

1. `claude-sovereign-compat` is contract-level, not runtime-level
2. Cloudflare/Cockpit naming and runtime ownership still need Kernel terminology
3. heavy peripherals such as `auto-video` still rely on budgeted verification instead of routine smoke
4. Claude-session-only MCP surfaces are now runtime-routable through Kernel, but some providers still rely on explicit fallback rather than full native ownership

These are not feature-drop blockers for the currently validated Kernel replacement set. They are expansion and hardening tasks.

## Conclusion

Kernel migration is substantially complete at the doctrine and interface level.

Kernel is now a strong implementation-level replacement for FUGUE, and live re-switch to FUGUE is runtime-complete through the explicit `fugue-bridge` path.

However, the hard part is now done:

- preserved doctrines are explicit
- peripheral compatibility is repeatedly validated
- rollback has a named adapter path
- remaining work is concentrated in optional adapter hardening and terminology cleanup
