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
- Keep repo secrets only for repo-specific credentials:
  - Example: `TARGET_REPO_PAT` (scope-limited PAT for PR creation)
- Use `selected` visibility unless the secret is truly safe to expose to all repos.

## Audit
Run:
```bash
scripts/audit-org-secrets.sh --org cursorvers
```

This checks:
- Required secret coverage per repo (org secret covers repo, or repo secret exists)
- Repo secrets that duplicate preferred org secrets (warns)

Config:
- `scripts/org-secrets-audit.json`
