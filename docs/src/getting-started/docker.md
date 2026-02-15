# Docker

This guide covers running Liteskill using Docker. This is the fastest way to get started -- no local Elixir, Erlang, or Node installation required.

## Docker Compose Quickstart

### 1. Create a `.env` File

Liteskill requires two secret keys: one for session signing and one for encrypting sensitive fields (API keys, MCP credentials) at rest. Generate them with OpenSSL:

```bash
cat <<EOF > .env
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '\n')
EOF
```

Docker Compose reads the `.env` file automatically from the project root.

> **Important:** Keep your `.env` file secure and never commit it to version control. The `SECRET_KEY_BASE` signs session cookies, and the `ENCRYPTION_KEY` protects API keys stored in the database. If you lose the `ENCRYPTION_KEY`, encrypted fields become unrecoverable.

### 2. Start the Application

```bash
docker compose up
```

This starts two services:

1. **db** -- PostgreSQL 16 with pgvector (`pgvector/pgvector:pg16`), storing data in a named volume (`pgdata`)
2. **app** -- The Liteskill application, which waits for the database to be healthy before starting

On first boot, the application automatically:

- Runs all pending database migrations (including pgvector extension setup)
- Creates the admin user (`admin@liteskill.local`)
- Starts the HTTP server on port 4000

Watch the logs for a line indicating the server is ready, then visit [http://localhost:4000](http://localhost:4000) in your browser.

> **Tip:** Run `docker compose up -d` to start in detached mode (background). Use `docker compose logs -f app` to follow the application logs.

### 3. First Login

See [First Run](first-run.md) for the complete walkthrough. The short version:

1. Visit [http://localhost:4000](http://localhost:4000)
2. Register a new account -- the first registered user is automatically made an admin
3. Complete the setup wizard (set admin password, optionally configure data sources)
4. Add LLM providers and models in the admin settings

### 4. Stop the Application

```bash
# Stop containers but keep the database volume (preserves all data)
docker compose down

# Stop containers AND delete the database volume (full reset)
docker compose down -v
```

### 5. Rebuild After Code Changes

If you modify the source code and want to rebuild the Docker image:

```bash
docker compose up --build
```

## Running Without Compose

If you already have a PostgreSQL instance with pgvector, or prefer plain `docker run`:

### Build the Image

```bash
docker build -t liteskill .
```

### Start the Server

```bash
docker run -d \
  --name liteskill \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/liteskill" \
  -e SECRET_KEY_BASE="$(openssl rand -base64 64 | tr -d '\n')" \
  -e ENCRYPTION_KEY="$(openssl rand -base64 32 | tr -d '\n')" \
  -e PHX_HOST="localhost" \
  liteskill
```

The container runs `bin/server` on startup, which automatically executes pending migrations before starting the HTTP server.

> **Note:** If your PostgreSQL is running on the host machine (not in Docker), use `--network host` instead of `-p 4000:4000` and set the `DATABASE_URL` host to `localhost`. On Docker Desktop for macOS/Windows, use `host.docker.internal` as the database host instead.

### Connect to an Existing PostgreSQL

Your PostgreSQL instance must:

- Be version 14 or later
- Have the [pgvector](https://github.com/pgvector/pgvector) extension available (it will be enabled automatically by migrations)
- Be reachable from the Docker container

## Environment Variable Reference

All configuration is loaded from environment variables at startup. The table below lists every variable the application recognizes.

### Required

| Variable | Description | How to Generate |
|----------|-------------|-----------------|
| `DATABASE_URL` | PostgreSQL connection string in Ecto format | `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | Signs and encrypts session cookies. Must be at least 64 bytes, base64-encoded. | `openssl rand -base64 64` |
| `ENCRYPTION_KEY` | Encrypts sensitive fields (API keys, MCP credentials) at rest using AES-256-GCM. Must be 32 bytes, base64-encoded. | `openssl rand -base64 32` |

> **Note:** When using Docker Compose, `DATABASE_URL` is constructed automatically from the `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` variables. You do not need to set it manually.

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP port the server listens on | `4000` |
| `PHX_HOST` | Public hostname for URL generation | `example.com` |
| `PHX_SERVER` | Set to `true` to start the HTTP server (set automatically by `bin/server`) | -- |
| `POOL_SIZE` | Database connection pool size | `10` |
| `ECTO_IPV6` | Set to `true` or `1` to use IPv6 for database connections | -- |
| `DNS_CLUSTER_QUERY` | DNS query for clustering multiple nodes | -- |
| `OIDC_ISSUER` | OpenID Connect issuer URL (enables SSO login) | -- |
| `OIDC_CLIENT_ID` | OIDC client ID | -- |
| `OIDC_CLIENT_SECRET` | OIDC client secret | -- |
| `AWS_BEARER_TOKEN_BEDROCK` | AWS Bedrock bearer token (only for legacy Bedrock RAG embeddings) | -- |
| `AWS_REGION` | AWS region for Bedrock (only for legacy Bedrock RAG embeddings) | -- |

### Docker Compose Defaults

The `docker-compose.yml` file sets defaults for the PostgreSQL container:

| Variable | Default |
|----------|---------|
| `POSTGRES_USER` | `liteskill` |
| `POSTGRES_PASSWORD` | `liteskill` |
| `POSTGRES_DB` | `liteskill` |

You can override these in your `.env` file if needed.

## Automatic Migrations

The Docker image includes a `bin/server` script that runs all pending database migrations before starting the HTTP server. You never need to run migrations manually when using Docker.

If you need to run migrations separately (for example, in a blue-green deployment where you migrate before switching traffic), use the `migrate` profile:

```bash
docker compose run --rm migrate
```

This runs `bin/migrate`, which executes `Liteskill.Release.migrate()` and exits.

## Image Tags

CI automatically builds and pushes images on every push to `main` and on version tags:

| Event | Tags | Pushed? |
|-------|------|---------|
| Push to `main` | `main`, `sha-<hash>` | Yes |
| Tag `v1.2.3` | `1.2.3`, `1.2`, `latest`, `sha-<hash>` | Yes |
| Pull request | `pr-<number>` | No (build-only) |

To use a published image instead of building locally, replace the `build: .` directive in `docker-compose.yml`:

```yaml
app:
  image: liteskill/liteskill:latest
  # ... rest of configuration unchanged
```

## Troubleshooting

**"SECRET_KEY_BASE is required" or "ENCRYPTION_KEY is required"**

Docker Compose validates required environment variables on startup. Make sure your `.env` file exists in the project root and contains both `SECRET_KEY_BASE` and `ENCRYPTION_KEY`. Re-generate them if needed:

```bash
cat <<EOF > .env
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '\n')
EOF
```

**Database connection refused**

If the app container cannot reach the database, check that the `db` service is healthy:

```bash
docker compose ps
```

The `db` service should show a status of `healthy`. If it is still starting up, wait a few seconds and try again. The app container is configured to wait for the database health check before starting.

**Port 4000 already in use**

Change the host port mapping in `docker-compose.yml` or your `docker run` command:

```bash
# Map to host port 8080 instead
docker run -d -p 8080:4000 ...
```

**Resetting everything**

To start completely fresh (delete all data, images, and volumes):

```bash
docker compose down -v --rmi local
```
