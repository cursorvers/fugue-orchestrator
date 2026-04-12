# Kernel Structure

`Kernel` is the Codex-first successor to the legacy Claude orchestration plane.

It keeps the inherited governance model, but centralizes sovereignty in the `gpt-5.4` Kernel while treating Claude, GLM, Gemini, MCPs, and linked systems as bounded adapters.

## Layered View

```text
┌─────────────────────────────────────────────────────────────────────┐
│ User / GitHub Issue / Cockpit / Discord / LINE / Scheduled Input   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ Kernel Intake                                                      │
│ - issue/comment intake                                              │
│ - Cockpit gateway                                                   │
│ - webhook normalization                                             │
│ - risk + task-size classification                                   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ Kernel Sovereign Core                                               │
│ - gpt-5.4 orchestrator                                              │
│ - plan / route / judge / ok_to_execute                              │
│ - adaptive lane topology                                            │
│ - evidence + trace generation                                       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ Kernel Unattended Runtime Substrate                                 │
│ - scheduler / claim / reconcile                                     │
│ - workspace lifecycle                                               │
│ - retry / continuation                                              │
│ - status + recovery surfaces                                        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
             ┌─────────────────┼──────────────────┐
             │                 │                  │
             v                 v                  v
┌─────────────────────┐ ┌──────────────────┐ ┌──────────────────────┐
│ Proposal Lanes      │ │ Council Lanes    │ │ Sovereign Adapters   │
│ - codex-spark xN    │ │ - Claude         │ │ - codex-sovereign    │
│ - architect         │ │ - GLM            │ │ - claude-compat      │
│ - implementer       │ │ - Gemini (UI)    │ │ - fugue-bridge       │
│ - critic            │ │ - xAI (realtime) │ │                      │
│ - verifier          │ │                  │ │                      │
└──────────┬──────────┘ └─────────┬────────┘ └──────────┬───────────┘
           │                      │                     │
           └──────────────┬───────┴──────────────┬──────┘
                          │                      │
                          v                      v
┌─────────────────────────────────────────────────────────────────────┐
│ Execution + Adapter Plane                                           │
│ - Claude executor / Agent Teams                                     │
│ - MCP adapters                                                      │
│ - linked systems bus                                                │
│ - local-agent / Cloudflare Workers                                  │
│ - specialist tooling                                                 │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ Peripheral Surfaces                                                 │
│ - Cloudflare Cockpit / WebSocket / notifications                    │
│ - Discord / LINE / note / video / Obsidian                          │
│ - Supabase / Vercel / Cursorvers protected interfaces               │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ Verification + Rollback                                             │
│ - Kernel peripheral simulation                                      │
│ - sovereign adapter switch simulation                               │
│ - fugue-bridge handoff                                              │
│ - evidence logs and run trace                                       │
└─────────────────────────────────────────────────────────────────────┘
```

## Control-Plane Diagram

```mermaid
flowchart TD
    U[User / GitHub / Cockpit / Webhook] --> I[Kernel Intake]
    I --> C[gpt-5.4 Kernel Core]
    C --> R[Risk + Task Size Classifier]
    R --> T[Adaptive Topology Router]
    T --> S[Unattended Runtime Substrate]

    S --> P1[codex-spark architect]
    S --> P2[codex-spark implementer]
    S --> P3[codex-spark critic]
    S --> P4[codex-spark verifier]

    S --> V1[Claude council / executor]
    S --> V2[GLM reviewer]
    S --> V3[Gemini UI reviewer]
    S --> V4[xAI realtime reviewer]

    P1 --> A[Council Aggregation]
    P2 --> A
    P3 --> A
    P4 --> A
    V1 --> A
    V2 --> A
    V3 --> A
    V4 --> A

    A --> G[ok_to_execute gate]
    G --> E[Execution adapters]

    E --> M[MCP adapters]
    E --> L[Linked systems bus]
    E --> W[Cloudflare / local-agent]
    E --> SP[Specialists]

    G --> F[fugue-bridge]
    F --> LF[Legacy Claude Orchestration]
```

## Reading Guide

- `Kernel Intake`
  - Normalizes entry points so GitHub, Cockpit, and webhook flows all reach the same Kernel packet contract.
- `Kernel Sovereign Core`
  - The only place that may decide lane topology, approve execution, and emit the final state transition.
- `Kernel Unattended Runtime Substrate`
  - Owns claim/reconcile/workspace/retry mechanics, but must not rewrite governance or create a
    second start-signal path.
- `Proposal Lanes`
  - Speed-focused exploration and implementation candidates, mainly Codex Multiagent and codex-spark.
- `Council Lanes`
  - Independent reviewers that contest or validate the proposal.
- `Execution + Adapter Plane`
  - Where Claude-native skills, MCPs, and linked systems are actually invoked.
- `Verification + Rollback`
  - Kernel is not considered healthy unless simulations pass and `fugue-bridge` remains runnable.

## Related Ops Docs

- [Kernel Recovery Runbook](/Users/masayuki/Dev/fugue-orchestrator/docs/kernel-recovery-runbook.md)
- [Kernel Mini/MBP Operations Topology](/Users/masayuki/Dev/fugue-orchestrator/docs/kernel-mini-mbp-ops-topology.md)
- [Kernel Tailscale / Railway Integration Design](/Users/masayuki/Dev/fugue-orchestrator/docs/kernel-tailscale-railway-integration-design.md)
