# Kernel Peripheral Adapter Contract

## Goal

Apply the same adapter discipline used for sovereign orchestrators to peripheral systems.

Kernel should not treat peripherals as ad hoc side effects.
Kernel should treat them as typed adapters with explicit authority, validation, and contract ownership.

## Core Rule

Peripheral systems may produce artifacts, notifications, or side effects.

They may not become control-plane truth.

Control-plane truth remains in Kernel.

## Required Fields

Each peripheral adapter should declare:

- `id`
- `scope`
  - `local-linked`
  - `cross-repo`
  - `skill`
- `kind`
  - `content`
  - `knowledge`
  - `notify`
  - `service`
  - `ui`
  - `artifact`
- `adapter_class`
  - `shell`
  - `worker-service`
  - `external-contract`
  - `skill`
- `authority`
  - `artifact-only`
  - `service-adapter`
  - `gateway`
  - `protected-external`
  - `ui-boundary`
- `validation_mode`
  - `smoke`
  - `budgeted`
  - `regression`
  - `contract`
- `contract_owner`
  - `kernel-local`
  - `cloudflare`
  - `cursorvers-line`
  - `vercel`
  - `external`
- `preferred_lane`
  - `codex`
  - `claude`
  - `cloudflare`
  - `external`
- `protected_interface`

Ingress-facing adapters should also declare:

- `ingress_surface`
  - `public-web`
  - `public-webhook`
  - `private-admin-ui`
  - `service-private`
- `ingress_auth`
  - `webhook-signature`
  - `tailscale-auth`
  - `session-auth`
  - `service-to-service`
- `accepts_signed_payload`
- `routing_domain`
- `dedupe_strategy`
  - required for `gateway` adapters
- `fail_closed`
  - required and `true` for `gateway` adapters

## Authority Model

### `artifact-only`

- adapter may generate notes, videos, slides, or knowledge artifacts
- result returns to Kernel as evidence, never as state authority

### `service-adapter`

- adapter connects Kernel to a service boundary
- examples:
  - Discord notify
  - LINE notify

### `gateway`

- adapter is an ingress or authoritative runtime boundary
- example:
  - Cloudflare Discord ingress
- must define explicit ingress auth, routing domain, and fail-closed behavior

### `protected-external`

- business-critical system in another repo/runtime
- Kernel must integrate with it, not absorb it by default
- example:
  - Cursorvers LINE platform

### `ui-boundary`

- deployment or hosting boundary for UI surfaces
- example:
  - Vercel cockpit UI

## Validation Policy

### `smoke`

- cheap, frequent, default validation

### `budgeted`

- heavy validation that should be sampled or run only when relevant

### `regression`

- code or service regression tests in the owning repo/runtime

### `contract`

- static or cross-repo contract verification

## Current Manifest Structure

The current manifests are:

- `config/integrations/local-systems.json`
- `config/integrations/peripheral-adapters.json`

The first is runner-facing.
The second is Kernel architecture-facing.

## Current Validation Entry Points

- `scripts/check-linked-systems-integrity.sh`
- `scripts/check-peripheral-adapters.sh`
- `scripts/sim-kernel-peripherals.sh`

## Design Consequences

1. local linked systems can remain lightweight shell adapters
2. heavy peripherals can be marked `budgeted` instead of blocking every loop
3. protected business systems can stay external while still being part of Kernel verification
4. Cloudflare, Supabase, Vercel, and Cursorvers LINE can all be modeled under one adapter vocabulary
