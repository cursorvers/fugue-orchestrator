# Kernel / FUGUE Secret Plane Design

Goal: make `Kernel` and `FUGUE` interchangeable at the orchestration layer without moving or renaming secrets, while reducing the chance that agents read secrets from the workspace.

## Core Principle

The source of truth is **not** `.env` in the repository. The source of truth is the secret store closest to the execution boundary.

This is a hard rule, not a convenience preference:

- do not store live secrets in repository `.env*` files
- do not assume agents or LLM tools will ignore workspace env files
- do not treat workspace-local secret files as a long-term fallback

## Secret Planes

```text
                    +-----------------------------+
                    | Secret Contract Layer       |
                    | stable canonical names      |
                    | OPENAI_API_KEY              |
                    | ANTHROPIC_API_KEY           |
                    | ZAI_API_KEY                 |
                    | TARGET_REPO_PAT             |
                    | FUGUE_OPS_PAT               |
                    +-------------+---------------+
                                  |
          +-----------------------+-----------------------+
          |                                               |
          v                                               v
+-----------------------------+              +-----------------------------+
| CI Secret Plane             |              | Runtime Secret Plane        |
| GitHub Org Secrets          |              | Supabase / Cloudflare /     |
| GitHub Repo Secrets         |              | Vercel / Fly secret stores  |
| GitHub Environment Secrets  |              |                             |
+-------------+---------------+              +-------------+---------------+
              |                                              |
              v                                              v
      +-------+--------+                           +---------+--------+
      | Kernel CI      |                           | Supabase/Workers |
      | FUGUE CI       |                           | app runtimes      |
      +-------+--------+                           +---------+--------+
              \                                              /
               \                                            /
                +----------------+--------------------------+
                                 |
                                 v
                     +-------------------------+
                     | Local Bootstrap Plane   |
                     | encrypted bundle ->     |
                     | Keychain / process env  |
                     +-------------------------+
```

## Design Rules

### 1. Canonical names are orchestrator-agnostic

`Kernel` and `FUGUE` must consume the same names:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `ZAI_API_KEY`
- `GEMINI_API_KEY`
- `XAI_API_KEY`
- `TARGET_REPO_PAT`
- `FUGUE_OPS_PAT`
- platform-specific runtime names such as `SUPABASE_SERVICE_ROLE_KEY`

Swapping orchestrators changes routing and policy, not secret names.

### 2. CI and runtime stores are separate

- GitHub Actions secrets exist to run CI/CD and automation.
- Platform secrets exist to run deployed services.
- A runtime service should not depend on a repo `.env`.

Example:

- Cloudflare workers read Wrangler/Workers secrets

### 3. `.env` is bootstrap-only

Allowed:

- sourcing an external env file into the current shell
- one-shot hydrate into Keychain / process env
- one-shot sync into GitHub or platform secret stores
- local-only `.env.example` templates with dummy values

Not allowed:

- keeping live secrets in repo root
- keeping live secrets in any repository `.env*` file
- making workspace `.env` the operational source of truth
- relying on agents to “not read” local secret files

If an agent can read files in the workspace, assume it can inspect `.env`, `.env.local`, and similar files.

### 4. Shared vs repo-specific vs environment-specific

Use this split:

- **Organization secrets**
  - shared model/provider keys
  - shared notification lifelines
  - shared ops automation tokens
- **Repository secrets**
  - repo-specific tokens
  - repo-local webhooks or overrides
- **Environment secrets**
  - production/staging variants of the same repo secret
- **Platform secrets**
  - actual runtime credentials for Supabase/Cloudflare/Vercel/Fly

## Recommended Layout

### GitHub Organization Secrets

- `OPENAI_API_KEY`
- `ZAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- `XAI_API_KEY`
- `FUGUE_OPS_PAT`
- shared webhook fallbacks such as `DISCORD_WEBHOOK_URL`

Visibility should be `selected`, not `all`, unless the blast radius is explicitly acceptable.

### GitHub Repository / Environment Secrets

- `TARGET_REPO_PAT`
- repo-specific deploy tokens
- production-only overrides
- repo-specific human-gated secrets

### Platform Runtime Secrets

- Supabase:
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `LINE_CHANNEL_ACCESS_TOKEN`
  - `MANUS_API_KEY`
- Cloudflare:
  - `WORKERS_API_KEY`
  - webhook/auth secrets
- Vercel/Fly:
  - runtime app secrets only

## Swapback Safety

To keep rollback to `FUGUE` safe:

1. Keep canonical secret names stable.
2. Keep provider keys available even if one orchestrator is primary.
3. Put orchestrator-specific gating in policy, not in secret naming.
4. Never require a “secret migration” to move between `Kernel` and `FUGUE`.

This means:

- `Kernel` may treat `ANTHROPIC_API_KEY` as optional
- `FUGUE` may treat `OPENAI_API_KEY` or `ZAI_API_KEY` as optional
- but the names remain present and auditable in the same secret plane

## Rotation Policy

- rotate shared automation tokens every 90 days
- rotate immediately on `401 Bad credentials`
- do not keep invalid tokens as dormant secrets; replace or delete them
- audit coverage by name only, never by printing values

## Local Operator Workflow

Preferred:

```bash
export OPENAI_API_KEY=...
export ZAI_API_KEY=...
bash scripts/local/bootstrap-prod-secrets.sh --repo cursorvers/fugue-orchestrator --dry-run
```

Allowed fallback:

```bash
bash scripts/local/bootstrap-prod-secrets.sh \
  --env-file /secure/outside-workspace/cursorvers-bootstrap.env \
  --repo cursorvers/fugue-orchestrator \
  --dry-run
```

Avoid:

```bash
cd repo
cp .env.example .env
# then keep live secrets in the repo workspace
```

## Recommended Default

For this workspace, the best default is:

- no live `.env` in the repo
- one shared encrypted bundle for bootstrap / restore
- Keychain as the default local execution layer
- GitHub Org/Repo/Environment Secrets for CI
- Supabase/Cloudflare/Vercel/Fly secrets for runtime
- external env file only as explicit fallback
- same secret contract for `Kernel` and `FUGUE`

## Shared Local Resolver

`Kernel` and `FUGUE` should converge on one local resolution order for shared secrets:

1. process env
2. Keychain
3. explicit external env file

Routine runtime should not decrypt the shared bundle on every invocation. Decryption belongs to bootstrap / restore.
