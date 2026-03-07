# GitHub Actions Org Secret Migration

Goal: move GitHub Actions secrets to an org-first model while keeping `Kernel` and `FUGUE` reversible and preserving runtime secrets on their platforms.

## Rule

- If a secret is only used by GitHub Actions, prefer **Organization Secret** with `selected repositories`.
- If a secret is used by a deployed runtime, the runtime copy remains on the platform.
- If GitHub Actions must sync that runtime secret during deploy, controlled duplication is allowed:
  - GitHub Org Secret = CI distribution source
  - Platform Secret = runtime source of execution

## Migration Matrix

### Move to GitHub Organization Secrets

- `OPENAI_API_KEY`
- `ZAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `DISCORD_ADMIN_WEBHOOK_URL`
- `DISCORD_WEBHOOK_URL`
- `DISCORD_SYSTEM_WEBHOOK`
- `N8N_API_KEY`
- `N8N_INSTANCE_URL`
- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_ID`
- `SUPABASE_URL`
- `MANUS_AUDIT_API_KEY`
- `MANUS_FIXER_API_KEY`
- `GOOGLE_SERVICE_ACCOUNT_JSON`
- `PROGRESS_WEBHOOK_URL`

### Keep as Repo / Environment Secret

- `TARGET_REPO_PAT`
- environment-specific deploy tokens
- any repo-specific webhook override

### Keep on Platform Runtime

- `SUPABASE_SERVICE_ROLE_KEY`
- `LINE_CHANNEL_ACCESS_TOKEN`
- `LINE_CHANNEL_SECRET`
- `MANUS_API_KEY`
- Cloudflare runtime auth/webhook secrets

## Controlled Duplication

These may exist both in GitHub Org Secrets and platform secrets on purpose:

- `LINE_CHANNEL_ACCESS_TOKEN`
- `LINE_CHANNEL_SECRET`
- `MANUS_API_KEY`

Reason:

- GitHub Actions may need them to smoke-test or sync to Supabase
- Supabase still needs them as runtime secrets

This is acceptable when GitHub is used as the CI distribution source and the platform remains the runtime execution source.

## Rotation Notes

- `MANUS_GITHUB_TOKEN` is currently a rotation target if `GitHub API 401 Bad credentials` appears.
- Prefer a GitHub App over long-lived PAT where possible.

## Audit

Use:

```bash
bash scripts/audit-org-secrets.sh --org cursorvers
```

Config source:

- [org-secrets-audit.json](/Users/masayuki/Dev/fugue-orchestrator/scripts/org-secrets-audit.json)
