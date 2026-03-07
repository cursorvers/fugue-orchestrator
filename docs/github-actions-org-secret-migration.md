# GitHub Actions Org Secret Migration

Goal: move GitHub Actions secrets to an org-first model while keeping `Kernel` and `FUGUE` reversible and preserving runtime secrets on their platforms.

## Rule

- If a secret is only used by GitHub Actions, prefer **Organization Secret** with `selected repositories`.
- Use `ALL` only by exception. The default should be `selected repositories`.
- If a secret is used by a deployed runtime, the runtime copy remains on the platform.
- If GitHub Actions must sync that runtime secret during deploy, controlled duplication is allowed:
  - GitHub Org Secret = CI distribution source
  - Platform Secret = runtime source of execution

## Migration Matrix

### Move to GitHub Organization Secrets

- `OPENAI_API_KEY`
- `ZAI_API_KEY`
- `XAI_API_KEY`
- `DISCORD_ADMIN_WEBHOOK_URL`
- `DISCORD_WEBHOOK_URL`
- `DISCORD_SYSTEM_WEBHOOK`
- `N8N_API_KEY`
- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_URL`
- `MANUS_AUDIT_API_KEY`
- `GOOGLE_SERVICE_ACCOUNT_JSON`
- `PROGRESS_WEBHOOK_URL`

### Optional GitHub Organization Secrets

- `ANTHROPIC_API_KEY`

### Move to GitHub Organization Variables

- `SUPABASE_PROJECT_ID`
- `N8N_INSTANCE_URL`

### Keep as Repo / Environment Secret

- `TARGET_REPO_PAT`
- environment-specific deploy tokens
- any repo-specific webhook override

### Keep on Platform Runtime

- `SUPABASE_SERVICE_ROLE_KEY`
- `LINE_CHANNEL_ACCESS_TOKEN`
- `LINE_CHANNEL_SECRET`
- `MANUS_API_KEY`
- `MANUS_FIXER_API_KEY`
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

To sync available current-shell or external-file values across every configured repo:

```bash
bash scripts/local/sync-gh-secrets-matrix.sh --org cursorvers --dry-run
```

Apply mode:

```bash
bash scripts/local/sync-gh-secrets-matrix.sh --org cursorvers --apply
```

If the current `gh` identity does not have org-level secret access, the script now
falls back to repo-only classification and prints:

- secrets that should migrate from repo to org
- required coverage that cannot be verified without org access
- repo-specific exceptions that may remain in repo/environment scope

This lets migration planning continue before org permissions are granted.

## Minimum Access Model

For long-term operations, the best setup is:

- a dedicated GitHub automation identity or GitHub App for secret management
- org permission to manage Actions organization secrets and variables
- repo/environment permissions only where a repo-specific exception is justified

For a human operator using `gh`, the minimum practical setup is:

```bash
gh auth refresh -h github.com -s admin:org,repo,read:org
```

And the GitHub account must have either:

- org owner access, or
- a custom role that can manage Actions organization secrets and variables

Without that, repo-level classification still works, but org coverage cannot be proven.

Config source:

- [org-secrets-audit.json](/Users/masayuki/Dev/fugue-orchestrator/scripts/org-secrets-audit.json)
