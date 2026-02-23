# Environment Variables

## Required (Production)

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string (e.g. `ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | Phoenix secret key (generate with `mix phx.gen.secret`) |
| `ENCRYPTION_KEY` | Key for AES-256-GCM encryption of sensitive fields (32+ chars) |
| `PHX_SERVER` | Set to `true` to start the HTTP server (required for releases) |

## Server

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | HTTP port |
| `PHX_HOST` | `example.com` | Hostname for URL generation |
| `ECTO_IPV6` | — | Set to `true` or `1` to enable IPv6 for database connections |
| `POOL_SIZE` | `10` | Database connection pool size |
| `DNS_CLUSTER_QUERY` | — | DNS query for node clustering |

## Authentication

| Variable | Description |
|----------|-------------|
| `OIDC_ISSUER` | OpenID Connect issuer URL |
| `OIDC_CLIENT_ID` | OIDC client ID |
| `OIDC_CLIENT_SECRET` | OIDC client secret |

## LLM

| Variable | Description |
|----------|-------------|
| `AWS_BEARER_TOKEN_BEDROCK` | AWS Bedrock bearer token (auto-creates instance-wide provider on boot) |
| `AWS_REGION` | AWS region for Bedrock (default: `us-east-1`) |

## Mode

| Variable | Description |
|----------|-------------|
| `SINGLE_USER_MODE` | Set to `true`, `1`, or `yes` to enable single-user mode |
| `LITESKILL_DESKTOP` | Set to `true` to enable desktop mode (bundled Postgres, auto-config) |

## Desktop Mode

When `LITESKILL_DESKTOP=true`:

- Data is stored in platform-specific directories:
  - macOS: `~/Library/Application Support/Liteskill`
  - Linux: `$XDG_DATA_HOME/liteskill` (default: `~/.local/share/liteskill`)
  - Windows: `%APPDATA%/Liteskill`
- Encryption key and secret key base are auto-generated and persisted in `desktop_config.json`
- Single-user mode is automatically enabled
- PostgreSQL connects via Unix socket (or TCP on Windows with `LITESKILL_PG_PORT`)

## Docker Compose

The `docker-compose.yml` expects these variables (with defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `liteskill` | PostgreSQL user |
| `POSTGRES_PASSWORD` | `liteskill` | PostgreSQL password |
| `POSTGRES_DB` | `liteskill` | PostgreSQL database name |
| `SECRET_KEY_BASE` | (required) | Phoenix secret key |
| `ENCRYPTION_KEY` | (required) | Encryption key |
| `PHX_HOST` | `localhost` | Public hostname |
| `AWS_BEARER_TOKEN_BEDROCK` | — | Optional Bedrock token |
| `AWS_REGION` | `us-east-1` | AWS region |

## ReqLLM

Configured in `runtime.exs` (not via env vars):

- `stream_receive_timeout`: 120,000ms
- `receive_timeout`: 120,000ms
- Finch pool: 25 connections, HTTP/1.1
