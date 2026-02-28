# Organization Secrets Strategy

Goal: minimize per-repository GitHub Actions secrets by centralizing shared credentials as GitHub **Organization secrets** (visibility: `selected`).

## Why
- Fewer duplicated secrets across repos
- Faster onboarding for new repos (just add to selected repositories)
- Smaller drift surface (1 place to rotate)

## Rules Of Thumb
- Put shared provider keys in org secrets:
  - `OPENAI_API_KEY`, `ZAI_API_KEY`
  - Optional specialists: `GEMINI_API_KEY`, `XAI_API_KEY`
  - Notification lifelines: `DISCORD_WEBHOOK_URL` (fallback: `DISCORD_SYSTEM_WEBHOOK`), `LINE_WEBHOOK_URL` (or `LINE_CHANNEL_ACCESS_TOKEN` + `LINE_TO`; legacy fallback: `LINE_NOTIFY_TOKEN`)
  - Ops token for variable/state auto-recovery: `FUGUE_OPS_PAT` (fallback: `TARGET_REPO_PAT`)
- Keep repo secrets only for repo-specific credentials:
  - Example: `TARGET_REPO_PAT` (scope-limited PAT for PR creation)
- Use `selected` visibility unless the secret is truly safe to expose to all repos.

## Audit
Run:
```bash
scripts/audit-org-secrets.sh --org cursorvers
```

Bootstrap/update secrets from local env:
```bash
bash scripts/local/sync-gh-secrets-from-env.sh --env-file /path/to/.env --dry-run
bash scripts/local/sync-gh-secrets-from-env.sh --env-file /path/to/.env --apply
```

One-command bootstrap (sync + audit):
```bash
bash scripts/local/bootstrap-prod-secrets.sh --env-file /path/to/.env --dry-run
bash scripts/local/bootstrap-prod-secrets.sh --env-file /path/to/.env --apply
```

This checks:
- Required secret coverage per repo (org secret covers repo, or repo secret exists)
- Repo secrets that duplicate preferred org secrets (warns)

Config:
- `scripts/org-secrets-audit.json`
  - `required`: all必須
  - `required_any`: 配列単位でOR条件（例: `LINE_WEBHOOK_URL` または `LINE_CHANNEL_ACCESS_TOKEN+LINE_TO`）
