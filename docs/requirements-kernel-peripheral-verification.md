# Requirements: Kernel Peripheral Verification Green Path

## 1. Goal

Make Kernel peripheral verification reproducibly green on an arm64 local development machine without
changing Kernel council semantics, sovereign adapter packet contracts, or linked-system authority
boundaries.

The target outcome is that Kernel can prove its surrounding integrations are connected and
contract-valid, while local dependency drift in dependent workspaces is handled explicitly instead of
being misread as a Kernel architecture failure.

## 2. Problem Statement

Current verification already proves the core Kernel connection surfaces are healthy:

- sovereign adapter contract passes
- linked-system smoke passes
- peripheral adapter contract passes
- MCP adapter contract and execution pass

The remaining failures are isolated to Cloudflare Workers side workspaces under
`../cloudflare-workers-hub-deploy`, where native optional dependencies for arm64 are missing during
local test/build execution.

Kernel therefore has a verification reliability gap, not a control-plane design gap.

## 3. Scope

### In Scope

- `scripts/sim-kernel-peripherals.sh`
- `scripts/check-sovereign-adapters.sh`
- preflight environment checks required by the verification harness:
  - required commands: `bash`, `jq`, `rg`, `npm`, `deno`
  - required workspaces: `../cloudflare-workers-hub-deploy`, `../cursorvers_line_free_dev`
- prerequisite workspace readiness for Workers-side verification
- dependency health of:
  - `../cloudflare-workers-hub-deploy`
  - `../cloudflare-workers-hub-deploy/local-agent`
  - `../cloudflare-workers-hub-deploy/cockpit-pwa`
- runbook/documentation needed to make the verification path reproducible

### Out of Scope

- changes to Kernel council math
- changes to sovereign adapter schema or governance invariants
- new peripheral features
- GitHub workflow or CI redesign
- production deploys or external notifications

## 4. Functional Requirements

1. Kernel verification must distinguish `contract failure` from `local dependency drift`.
2. `scripts/check-sovereign-adapters.sh` must remain green with no schema or governance regression.
3. `scripts/sim-kernel-peripherals.sh` must execute all declared checks and produce summary artifacts.
4. Workers-side local verification must succeed on arm64 once dependencies are correctly installed.
5. The verification path must document which external repos/workspaces are prerequisites.
6. The fix path must not require changing Kernel protocol packets or adapter authority boundaries.
7. Verification success must be based on a fixed expected check set/count, not on a reduced or
   implicitly skipped subset.

## 5. Non-Functional Requirements

1. Reproduction steps must fit in a short local runbook.
2. The recovery path should prefer minimal repair:
   - first: `npm install`
   - only later: destructive cleanup if install alone is insufficient
3. Verification evidence must be written under the fixed base directory
   `/Users/masayuki/Dev/tmp/kernel-peripheral-verification`, with one unique run directory per
   execution.
4. The result must be diagnosable from summary and per-check log files without deep manual tracing.

## 6. Current Known Failure Modes

### Dependency Drift

- missing `@rollup/rollup-darwin-arm64`
- missing `lightningcss.darwin-arm64.node`

### Misclassification Risk

- a local package-install problem could be mistaken for Kernel/peripheral contract breakage
- preflight command or workspace absence could be misread as a contract regression

### Hidden Environment Assumptions

- dependent workspaces may appear present but still be unusable because optional native packages were
  not installed for the current architecture
- required verification commands may be missing from the local shell environment
- checks may appear green if execution is silently reduced or skipped

## 7. Acceptance Criteria

The requirements are satisfied only when all of the following are true:

1. `bash scripts/check-sovereign-adapters.sh` exits `0`.
2. `bash scripts/sim-kernel-peripherals.sh` exits `0`.
3. `results.json` contains exactly 16 check IDs and no missing/extra entries:
   - each entry uses the harness schema (`id`, `status`, `workdir`, `duration_ms`, `log_file`,
     `message`)
   - `linked_integrity`
   - `peripheral_adapter_contract`
   - `mcp_adapter_contract`
   - `mcp_adapter_exec`
   - `claude_teams_policy`
   - `sovereign_adapter_contract`
   - `sovereign_adapter_switch_sim`
   - `fugue_bridge_runtime`
   - `kernel_canary_plan`
   - `orchestrator_matrix`
   - `linked_systems_smoke`
   - `workers_local_agent`
   - `workers_cockpit_pwa`
   - `workers_discord_regressions`
   - `cursorvers_functions`
   - `kernel_contract_probe`
4. Every `results.json` entry has `status == "ok"`.
5. `summary.md` counts match `results.json` re-computation (`checks`, `passed`, `failed`).
6. Workers-side failures no longer report missing arm64 optional dependencies.
7. No Kernel contract or adapter manifest changes were needed to achieve green verification unless a
   separate verified defect is found.
8. Documentation clearly states the prerequisite dependency state for dependent workspaces.

## 8. Stop Conditions

Stop and re-scope if any of the following becomes true:

- a failure moves from dependency health into sovereign adapter or governance contract failure
- the only path to green requires changing Kernel protocol semantics
- the dependent workspace requires destructive cleanup not yet explicitly approved
- any expected check ID is missing, extra check IDs are introduced without requirement updates, or
  check count drifts from `16`
- any check is skipped/reduced/suppressed to force green outcomes ("green by suppression")
- preflight command/workspace requirements are not met and cannot be resolved via dependency repair

## 9. Completion Proof

Completion proof for this work item consists of:

- one passing run of `scripts/check-sovereign-adapters.sh`
- one passing run of `scripts/sim-kernel-peripherals.sh`
- the resulting `results.json` and `summary.md` artifact paths
- one consistency check note confirming `summary.md` matches `results.json` counts
- a short note identifying repaired dependency roots and explicit repair commands executed

## 10. Recommended Implementation Path

1. Run preflight dependency checks for required commands and workspace paths.
2. Repair dependencies in `../cloudflare-workers-hub-deploy`.
3. Repair dependencies in `../cloudflare-workers-hub-deploy/local-agent`.
4. Repair dependencies in `../cloudflare-workers-hub-deploy/cockpit-pwa`.
5. Re-run Kernel verification.
6. Document prerequisites, repair commands, and evidence paths.
