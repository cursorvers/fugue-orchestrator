# Cloudflare Workers Hub Secret Classification (2026-03-07)

Purpose:

- classify the remaining `cloudflare-workers-hub` secrets into:
  - `org-shared CI`
  - `repo/env-specific CI`
  - `platform runtime`
- keep `Kernel` / `FUGUE` secret-plane rules consistent

## Promote To Org Secret

- `CLOUDFLARE_API_TOKEN`
  - shared deploy credential across multiple workflows
- `CLOUDFLARE_ACCOUNT_ID`
  - shared Cloudflare account identifier used by CI workflows
- `SENTRY_AUTH_TOKEN`
  - shared release/upload credential used by CI workflows

These are the best candidates for `org-first / selected-by-default`.

## Keep Repo Or Environment Specific

- `WORKERS_API_KEY`
- `WORKERS_API_URL`
- `QUEUE_API_KEY`
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `VAPID_SUBJECT`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `GCP_SERVICE_ACCOUNT_JSON_PATH`
- `GCP_BILLING_ACCOUNT_ID`
- `STRIPE_SECRET_KEY`
- `BACKFILL_API_KEY`
- `CODEX_AUTH_JSON`
- `XAI_API_KEY`
- `ZAI_API_KEY`

Reason:

- these are app/resource/environment specific
- broad org-wide visibility would increase blast radius
- several are tied to one worker deployment, one integration, or one external account

## Keep As Platform Runtime Secrets

- `SENTRY_DSN`
- `CF_ACCESS_AUD`
- any Worker secret consumed only at runtime

These should remain on the Cloudflare side, not GitHub.

## Script-Only Runtime Inventory

The following runtime/process env values are used in helper scripts and should be tracked separately from workflow-only CI secrets:

- `OPENAI_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ASSISTANT_API_KEY`
- `SLACK_BOT_TOKEN`
- `TELEGRAM_BOT_TOKEN`
- `DISCORD_WEBHOOK_URL`
- `SLACK_WEBHOOK_URL`
- `STRIPE_EMAIL`
- `STRIPE_PASSWORD`
- `STRIPE_TOTP_SECRET`
- `GOOGLE_APPLICATION_CREDENTIALS`
- `GOOGLE_CREDENTIALS_PATH`
- `GCP_PROJECT_ID`

## Current Recommendation

1. move `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SENTRY_AUTH_TOKEN` to org secrets
2. leave the rest repo/env-specific unless a concrete shared-use case emerges
3. do not mix runtime Worker secrets into GitHub org secrets
