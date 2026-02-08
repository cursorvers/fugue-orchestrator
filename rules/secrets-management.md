# Secrets Management Rules

## Principle

**Shared API keys go in Organization Secrets. Project-specific keys go in Repository Secrets.**

## Hierarchy

```
Organization Secrets (your GitHub org)     <- priority
+-- AI_API_KEY_GLM                         <- GLM-4.7
+-- AI_API_KEY_GEMINI                      <- Gemini
+-- AI_API_KEY_OPENAI                      <- Codex (if needed)
+-- (other shared API keys)

Repository Secrets                          <- project-specific only
+-- VERCEL_TOKEN                           <- deploy-specific
+-- SUPABASE_SERVICE_ROLE_KEY              <- DB-specific
+-- DISCORD_WEBHOOK_URL                    <- notification-specific
+-- (other project-specific keys)
```

## Decision Criteria

| Secret Type | Location | Reason |
|------------|---------|--------|
| AI API Keys (GLM, Gemini, OpenAI) | Organization | Shared across multiple repos |
| Deploy (Vercel, Netlify) | Repository | Project-specific |
| DB (Supabase, Firebase) | Repository | Project-specific |
| Notifications (Discord, Slack) | Repository | Project-specific |
| Auth (Clerk, Auth0) | Repository | Project-specific |

## When Adding a New Secret

1. **Shared across repos?** -> Yes -> Organization Secrets
2. **Project-specific?** -> Yes -> Repository Secrets
3. **Private repo on Free plan?** -> Repository Secrets (GitHub Free limitation)

## Local Development

```bash
# .env file (never committed)
GLM_API_KEY=your-key-here
GEMINI_API_KEY=your-key-here
OPENAI_API_KEY=your-key-here
```

## Prohibitions

- Never duplicate the same secret across multiple Repository Secrets
- Never hardcode secrets in source code
- Never commit `.env` files (ensure `.gitignore` covers them)
- Never store secrets in plaintext in documentation
