# Secrets Management Rules

## Principle

**Shared API keys go in Organization Secrets. Project-specific keys go in Repository Secrets.**

**Live secrets must never be stored in repository `.env` files.**

## Hierarchy

```
GitHub Organization Secrets (shared CI)    <- first choice for shared automation
+-- OPENAI_API_KEY
+-- ZAI_API_KEY
+-- ANTHROPIC_API_KEY
+-- GEMINI_API_KEY / XAI_API_KEY / ESTAT_API_ID
+-- shared webhook / ops credentials

GitHub Repository / Environment Secrets    <- repo- or env-specific CI only
+-- TARGET_REPO_PAT
+-- production-only deploy tokens
+-- repo-scoped notification overrides

Platform Runtime Secrets                   <- runtime systems of record
+-- Supabase Edge Function secrets
+-- Cloudflare Workers secrets
+-- Vercel / Fly / Railway runtime secrets

Local Process Environment                  <- runtime override only, never source of truth
+-- ephemeral shell/session override

Local Keychain / Secret Cache              <- local execution layer
+-- shared canonical names resolved for Mac mini / MBP runs
+-- hydrated from encrypted bundle during bootstrap / restore
```

## Decision Criteria

| Secret Type | Location | Reason |
|------------|---------|--------|
| AI API Keys (GLM, Gemini, OpenAI) | Organization | Shared across multiple repos |
| Deploy (Vercel, Netlify) | Repository or Environment | Project- / env-specific |
| DB (Supabase, Firebase) | Platform Runtime Secret | Runtime system of record |
| Notifications (Discord, Slack) | Org or Repo/Environment | Shared lifeline vs repo override |
| Auth (Clerk, Auth0) | Repository | Project-specific |
| Local bootstrap copy | Process env or explicit external env file | Temporary import only |

## When Adding a New Secret

1. **Shared across repos?** -> Yes -> Organization Secrets
2. **Project-specific?** -> Yes -> Repository Secrets
3. **Private repo on Free plan?** -> Repository Secrets (GitHub Free limitation)

## Local Development

```bash
# preferred: export into current shell, or source an env file outside the repo
export OPENAI_API_KEY=...
export ZAI_API_KEY=...
export ANTHROPIC_API_KEY=...
```

Do not treat `.env` inside the workspace as a trusted storage layer. Any agent or tool with file-read access may inspect repository files. If you must use an env file locally, keep it outside the repo and use it only to bootstrap Keychain/GitHub/platform secret stores.

Preferred local resolution order for shared secrets:

1. process env override
2. local Keychain/shared secret cache
3. shared encrypted SOPS bundle
4. explicit external env file

The encrypted shared bundle is the canonical bootstrap / restore source and a disaster-recovery fallback. Routine attended operation should be satisfied by process env or Keychain; explicit external env files are last-resort imports and must live outside the repository.

## Workspace Rule

- Do not create or keep live `.env`, `.env.local`, `.env.production`, or similar secret-bearing files inside repository workspaces.
- `.env.example` is allowed only with dummy placeholders.
- If a live env file is needed temporarily for bootstrap, place it outside the workspace and source it explicitly.
- `Kernel` and `FUGUE` secret operations must assume that workspace files are readable by tools and agents.

## Kernel / FUGUE Compatibility

- Secret **names** are the contract. Orchestrator choice must not require renaming secrets.
- `Kernel` and `FUGUE` should both resolve the same canonical names (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `ZAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, `ESTAT_API_ID`, `TARGET_REPO_PAT`, `FUGUE_OPS_PAT`, etc.).
- Provider-specific adapters may be optional, but secret naming stays stable so rollback from `Kernel` to `FUGUE` does not require secret migration.
- Shared local resolution should happen through a common loader, not by each orchestrator inventing its own lookup order.

## Prohibitions

- Never duplicate the same secret across multiple Repository Secrets
- Never hardcode secrets in source code
- Never commit `.env` files (ensure `.gitignore` covers them)
- Never keep live secrets in the repo workspace as the primary source of truth
- Never rely on “local `.env` is safe because the agent will not read it”
- Never store secrets in plaintext in documentation
