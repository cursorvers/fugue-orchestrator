# Kernel Tailscale / Railway Integration Design

## Goal

Integrate `Tailscale` and `Railway` into `Kernel` without letting either one
become sovereign control-plane truth.

This design should make three things true at the same time:

- `mac mini` remains the primary local execution host
- `GitHub Actions` remains the warm-standby continuity plane
- the legacy Claude-side path remains the rollback sovereign adapter

`Tailscale` and `Railway` are both support layers around that model:

- `Tailscale` is the private operator network and admin reachability layer
- `Railway` is the public ingress and light always-on service layer

## Decision Summary

| System | Kernel placement | Main role | What it must not become |
|---|---|---|---|
| `Tailscale` | execution/host transport layer | private operator access, host-to-host reachability, private admin UI exposure | public intake authority, orchestration truth, secret source of truth |
| `Railway` | peripheral service/runtime boundary | public HTTPS ingress, mobile web hosting, lightweight continuity helpers | sovereign core, heavy primary executor, durable run-state authority |

## Core Rules

1. `Kernel Sovereign Core` remains the only place that may decide routing,
   `ok_to_execute`, and final state transitions.
2. `Tailscale` may expose or connect hosts. It may not decide work.
3. `Railway` may receive, normalize, queue, and relay work. It may not approve
   or redefine work.
4. Public intake and private operator control must remain separate surfaces.
5. Runtime secrets stay in platform secret stores. No live secrets move into
   repo `.env*` files.
6. `GitHub` remains the neutral continuity substrate between local primary,
   Railway-hosted edges, and rollback/recovery paths.
7. Public intake must be fail-closed. Invalid signatures, unknown event types,
   duplicate delivery keys, or failed relays must not create partial execution.
8. Railway intake may hand off only into approved Kernel entry contracts. It
   must not invent new execution shortcuts around existing gates.

## Placement In Kernel

`Kernel` already separates the sovereign core from the execution and adapter
plane. `Tailscale` and `Railway` belong below that core.

- `Kernel Sovereign Core`
  - decides whether a task should stay local, use GitHub continuity, or roll
    back to `fugue-bridge`
  - decides whether a side effect is allowed
- `Execution + Adapter Plane`
  - uses `Tailscale` for private host reachability and operator access
  - uses `Railway` services as bounded gateways or protected external surfaces
- `Verification + Rollback`
  - must still validate `Kernel -> GitHub continuity`
  - must still validate `Kernel -> legacy Claude-side rollback`
  - may smoke-test Tailscale/Railway adapters, but neither one replaces the
    rollback contract

## How Tailscale Can Be Used

`Tailscale` should be treated as the private control and transport network for
operators and trusted hosts.

### Approved Uses

1. Private operator mesh
   - `mac mini`, `MBP`, phone, and any dedicated admin device join one tailnet
   - `MagicDNS` names give stable hostnames for `Kernel` ops tooling

2. Secure host access
   - `Tailscale SSH` provides attended remote access to `mac mini` and `MBP`
   - use this for intervention, debugging, and recovery when away from desk

3. Private admin UI exposure
   - expose `Happy` admin, `Cockpit`, or local health dashboards through
     `tailscale serve`
   - keep the actual service bound to loopback on the host
   - the default privileged UI path should be tailnet-only, not public internet

4. Host-to-host service reachability
   - allow `MBP` operator tools to hit the local `Kernel` primary safely
   - allow trusted service-to-host callbacks inside the tailnet when needed

5. Access segmentation
   - use ACLs/tags so only operator identities and tagged devices can reach
     privileged ports or SSH targets
   - privileged UIs must require an explicit operator allowlist or tagged-device
     policy; tailnet membership alone is not sufficient

6. Admin-surface auditability
   - privileged admin access should leave an auditable trail through host logs,
     Tailscale identity, or both
   - break-glass access should stay operator-only and time-bounded

### What Tailscale Should Not Do

- it should not be the public front door for normal user/webhook intake
- it should not be the queue or durable event log
- it should not be the approval authority
- it should not be the only recovery path

### Funnel Policy

`tailscale funnel` is optional and should be treated as exception-only.

Allowed cases:

- temporary demos
- emergency sharing of a bounded read-only page
- short-lived diagnostics when no better public edge exists

Disallowed as default:

- privileged operator UI
- general production intake
- long-lived public control surfaces

Reason:

- Funnel intentionally crosses from private tailnet access into public exposure
- this conflicts with the principle that privileged `Kernel` controls stay
  private by default

## How Railway Can Be Used

`Railway` should be treated as the always-on public edge and lightweight hosted
service layer around `Kernel`.

### Approved Uses

1. Public HTTPS intake gateway
   - host a small `kernel-edge-intake` service
   - receive webhooks, `Happy` mobile commands, or external callbacks
   - normalize them into the same neutral `Kernel intake packet`
   - relay only into approved `Kernel` handoff surfaces:
     - GitHub issue/comment intake
     - protected `workflow_dispatch` paths already used by Kernel recovery or
       routing
     - explicit future handoff contracts documented in this repo
   - do not relay directly into heavy execution lanes or ad hoc provider calls

2. Mobile/PWA delivery
   - host `Happy`-style public or semi-public web surfaces
   - keep operator-only views behind stronger auth and, when appropriate,
     behind `Tailscale`

3. Lightweight continuity helpers
   - scheduled digest jobs
   - stale-run nudges
   - status mirroring
   - notification fanout that does not require local heavy execution

4. Public callback termination
   - receive third-party webhooks that cannot reach a tailnet-only host
   - verify signatures
   - convert raw provider payloads into bounded, auditable envelopes for Kernel

5. Stateless service composition
   - use Railway public networking for HTTPS ingress
   - use Railway private networking for service-to-service communication inside
     a hosted edge stack

### Intake Contract Rules

Every `Railway` intake event must carry or derive:

- `ingress_event_id`
- `ingress_source`
- `received_at`
- `signature_verified`
- `dedupe_key`

Rules:

- the same `dedupe_key` must not be handed off twice inside the replay window
- duplicate deliveries may be acknowledged, but must not create a second
  orchestration start
- unverified or partially verified events must be rejected before handoff
- normalized packets must be immutable once handed off

Recommended default:

- set `dedupe_key` from provider delivery id when available
- otherwise derive it from source + external id + normalized intent hash
- keep a bounded replay window and reject or no-op duplicates within it

### Failure Policy

`Railway` intake must fail closed.

Allowed outcomes:

- `accepted-and-relayed`
- `duplicate-noop`
- `rejected-invalid-signature`
- `rejected-unknown-event`
- `rejected-policy`
- `deferred-relay-failure`

Rules:

- do not partially relay
- do not silently drop
- if GitHub or the approved handoff substrate is unreachable, emit a receipt
  with `deferred-relay-failure` and keep the event out of execution
- retries must reuse the same `dedupe_key`

### What Railway Should Not Do

- it should not become the `Kernel Sovereign Core`
- it should not replace `mac mini` as the primary heavy execution host
- it should not replace `GitHub Actions` as the official warm-standby
  continuity plane
- it should not hold the canonical durable run ledger
- it should not be the only location of operational secrets

### Volume Policy

Railway Volumes are acceptable for:

- setup state for a hosted UI
- temporary spool/cache
- local exports and bounded evidence mirrors

Railway Volumes are not the preferred home for:

- canonical `Kernel` run state
- sole durable decision journals
- irreplaceable orchestration evidence

If durable cross-host orchestration state is needed, keep it in already
approved truth layers such as GitHub artifacts/state, existing platform data
stores, or explicit external runtime systems.

## Combined Topology

The clean split is:

- `Railway` handles the public edge
- `Tailscale` handles the private admin mesh
- `mac mini` handles primary local execution
- `GitHub Actions` handles warm-standby continuity

```text
Public user / webhook / Happy mobile
  -> Railway edge intake
  -> normalized Kernel packet
  -> GitHub issue / dispatch / continuity substrate
  -> Kernel routing
       -> mac mini primary execution
       -> GitHub Actions standby continuity
       -> fugue-bridge rollback

Operator phone / MBP / trusted admin device
  -> Tailscale tailnet
  -> mac mini private admin UI / SSH / health endpoints
  -> attended intervention or review
```

Important boundary:

- `Railway` does not need to join the tailnet
- `Tailscale` does not need to become the public edge
- both stay replaceable because the neutral handoff packet remains the contract

## Contribution To Kernel Orchestration

### 1. Better ingress separation

Today, public intake, private control, and recovery can easily collapse into the
same surfaces. With this design:

- `Railway` becomes the public ingress boundary
- `Tailscale` becomes the private admin boundary
- `Kernel` keeps one normalized intake contract across both

This reduces accidental exposure of privileged local surfaces.

### 2. Better local-first execution

`Kernel` already wants local primary execution on `mac mini`. `Tailscale`
supports that by making the primary host reachable without making it public.

This keeps:

- local tools local
- private dashboards private
- remote operator access available from phone or `MBP`

### 3. Better continuity without changing sovereignty

`Railway` can stay alive when the local host sleeps, reboots, or temporarily
loses reachability.

This means:

- public commands can still be accepted
- webhooks do not bounce just because the primary host is unavailable
- status or digest surfaces can stay available
- the eventual execution decision still lands in `Kernel` or `GitHub`
  continuity, not inside Railway itself

### 4. Better mobile-first operations

The existing `Happy` direction wants one mobile-first front door. Railway is a
good fit for hosting the public/mobile shell, while Tailscale is a good fit for
the private operator path.

This creates a clean split:

- public/mobile product surface on `Railway`
- private/operator control on `Tailscale`

### 5. Better reversibility

Because neither Tailscale nor Railway becomes sovereign truth:

- `Kernel -> GitHub continuity` still works
- `Kernel -> legacy Claude-side rollback` still works
- host or platform changes do not force orchestration redesign

## Kernel Phase Mapping

| Kernel phase | Tailscale role | Railway role | Authority boundary |
|---|---|---|---|
| Intake classify | none by default | accept public request, verify auth/signature, normalize packet | Railway may normalize, not decide |
| Preflight enrich | operator can reach private tools over tailnet | host public/mobile UI and low-risk enrich helpers | Core decides whether enrich is relevant |
| Route / plan | none | none or relay-only | Core only |
| Execute | private reachability to local host and admin tools | optional relay/status only | Execution approval stays in Core |
| Recovery | operator reaches `mac mini` privately by SSH/Serve | keeps public status/intake alive, can dispatch into GitHub continuity | GitHub + Core remain continuity authority |
| Rollback | no sovereign role | no sovereign role | `fugue-bridge` remains rollback path |

## Adapter Model

If modeled in `config/integrations/peripheral-adapters.json`, the first entries
should look like this conceptually:

- `tailscale-admin-ui`
  - `scope`: `cross-repo`
  - `kind`: `ui`
  - `adapter_class`: `external-contract`
  - `authority`: `ui-boundary`
  - `validation_mode`: `smoke`
  - `contract_owner`: `external`
  - `preferred_lane`: `external`
  - `protected_interface`: `true`

- `railway-kernel-edge-intake`
  - `scope`: `cross-repo`
  - `kind`: `service`
  - `adapter_class`: `worker-service`
  - `authority`: `gateway`
  - `validation_mode`: `contract`
  - `contract_owner`: `external`
  - `preferred_lane`: `external`
  - `protected_interface`: `true`

- `railway-happy-web-boundary`
  - `scope`: `cross-repo`
  - `kind`: `ui`
  - `adapter_class`: `external-contract`
  - `authority`: `ui-boundary`
  - `validation_mode`: `contract`
  - `contract_owner`: `external`
  - `preferred_lane`: `external`
  - `protected_interface`: `true`

## Secrets And Identity

Apply the existing secret-plane rules directly:

- `Tailscale` auth stays in Tailscale identity/admin policy, not repo files
- Railway service secrets stay in Railway runtime variables
- GitHub CI secrets stay in GitHub Org/Repo/Environment secrets
- no live credentials go into workspace `.env*`

Practical consequences:

- `Railway` may store service-local runtime variables for public edge services
- `Tailscale` identity policy controls who may reach private admin surfaces
- neither one changes canonical secret names used by `Kernel` and the legacy Claude-side path

## Failure Model

### Normal

- public ingress arrives on `Railway`
- private admin access goes through `Tailscale`
- primary execution stays on `mac mini`

### Local primary degraded

- `Railway` still accepts intake and publishes status
- operator uses `Tailscale` to diagnose or intervene if the host is reachable
- if primary is truly unavailable, `GitHub Actions` continuity takes over

### Tailnet degraded

- private operator access is reduced
- public intake on Railway still works
- phone-based recovery through GitHub remains available

### Railway degraded

- public edge may be impaired
- direct GitHub/mobile recovery still works
- private Tailscale admin path still works

This is the desired resilience property:

- no single addition should become a new single point of orchestration truth

## Initial Implementation Sequence

1. `Tailscale` baseline
   - join `mac mini`, `MBP`, and operator phone to one tailnet
   - enable `MagicDNS`
   - define ACL/tag policy for admin hosts
   - expose one private admin UI through `tailscale serve`
   - verify `Tailscale SSH` to `mac mini`

2. `Railway` edge baseline
   - deploy a minimal `kernel-edge-intake`
   - support authenticated request normalization only
   - dispatch into existing GitHub intake/recovery workflows
   - do not run heavy execution here

3. `Happy` split
   - host the public/mobile shell on `Railway`
   - keep privileged admin views tailnet-only or separately gated

4. Continuity helpers
   - add lightweight Railway cron/status jobs
   - keep them receipt-oriented and non-sovereign

5. Contract registration
   - register Tailscale/Railway adapters in peripheral manifests
   - add smoke/contract checks to `sim-kernel-peripherals.sh` and related
     integrity scripts

## Non-Goals

- replacing `GitHub Actions` as the documented warm-standby plane
- making Railway the canonical run database
- exposing privileged `Kernel` admin controls to the public internet by default
- requiring public clients to join Tailscale
- coupling `Kernel` routing policy to one hosting vendor

## Related Docs

- [Kernel Structure](./kernel-structure.md)
- [Kernel Mini/MBP Operations Topology](./kernel-mini-mbp-ops-topology.md)
- [Kernel Recovery Runbook](./kernel-recovery-runbook.md)
- [Kernel Peripheral Adapter Contract](./kernel-peripheral-adapter-contract.md)
- [Kernel / legacy Claude Secret Plane Design](./kernel-fugue-secret-plane.md)
- [Kernel Happy.app Single-Front Architecture](./kernel-happy-app-single-front-architecture.md)

## External Capability References

- Tailscale `serve`: https://tailscale.com/docs/reference/tailscale-cli/serve
- Tailscale `funnel`: https://tailscale.com/docs/reference/tailscale-cli/funnel
- Tailscale `MagicDNS`: https://tailscale.com/docs/features/magicdns
- Tailscale access control: https://tailscale.com/docs/features/access-control/acls
- Tailscale SSH: https://tailscale.com/docs/features/tailscale-ssh
- Railway volumes: https://docs.railway.com/volumes/reference
- Railway private networking: https://docs.railway.com/networking/private-networking
- Railway variables: https://docs.railway.com/variables/reference
- Railway cron jobs: https://docs.railway.com/cron-jobs
- Railway healthchecks: https://docs.railway.com/deployments/healthchecks
