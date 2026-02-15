# Environment Variables

Liteskill is configured through environment variables, following the twelve-factor app methodology. This page documents all supported variables.

## Required Variables

These variables must be set in production. Development and test environments use defaults from `config/dev.exs` and `config/test.exs`.

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `ecto://user:pass@host/liteskill` |
| `SECRET_KEY_BASE` | Phoenix signing/encryption key for cookies and sessions. Generate with `mix phx.gen.secret` or `openssl rand -base64 64`. | 64+ character base64 string |
| `ENCRYPTION_KEY` | AES-256-GCM key for encrypting secrets at rest (API keys, provider configs). Generate with `openssl rand -base64 32`. | 32+ character base64 string |

## Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP port the server listens on | `4000` |
| `PHX_HOST` | Public hostname for URL generation | `example.com` |
| `PHX_SERVER` | Set to `true` to start the HTTP server (required for releases) | -- |
| `POOL_SIZE` | Database connection pool size | `10` |
| `ECTO_IPV6` | Set to `true` or `1` to enable IPv6 for database connections | -- |
| `DNS_CLUSTER_QUERY` | DNS query for cluster node discovery | -- |
| `FORCE_SSL` | Set to `false` to disable SSL enforcement (e.g., when TLS is terminated externally without `X-Forwarded-Proto`) | `true` (SSL enforced) |

## OIDC Variables

Set all three to enable OpenID Connect single sign-on. When `OIDC_CLIENT_ID` is not set, OIDC is disabled.

| Variable | Description | Default |
|----------|-------------|---------|
| `OIDC_ISSUER` | OpenID Connect issuer URL (e.g., `https://accounts.google.com`) | -- |
| `OIDC_CLIENT_ID` | OIDC client ID from your identity provider | -- |
| `OIDC_CLIENT_SECRET` | OIDC client secret from your identity provider | -- |

## AWS Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_BEARER_TOKEN_BEDROCK` | AWS Bedrock bearer token (used for legacy RAG embeddings via Cohere) | -- |
| `AWS_REGION` | AWS region for Bedrock API calls | `us-east-1` |

> **Note:** LLM provider credentials (API keys for Claude, GPT, etc.) are configured through the admin UI at `/admin/providers`, not through environment variables. The AWS variables above are specifically for the legacy Bedrock RAG embedding integration.

## Generating Secrets

For production deployments, generate the required secrets:

```bash
# Generate SECRET_KEY_BASE
openssl rand -base64 64

# Generate ENCRYPTION_KEY
openssl rand -base64 32
```

## Example `.env` File

For use with Docker Compose:

```env
# Required
POSTGRES_USER=liteskill
POSTGRES_PASSWORD=your-db-password
POSTGRES_DB=liteskill
SECRET_KEY_BASE=your-secret-key-base-here
ENCRYPTION_KEY=your-encryption-key-here

# AWS (for LLM access)
AWS_BEARER_TOKEN_BEDROCK=your-bedrock-token
AWS_REGION=us-east-1

# Optional: OIDC
# OIDC_ISSUER=https://accounts.google.com
# OIDC_CLIENT_ID=your-client-id
# OIDC_CLIENT_SECRET=your-client-secret
```
