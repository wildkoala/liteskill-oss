# Production Release

Liteskill can be deployed as a self-contained Elixir release or as a Docker container. This guide covers both approaches.

## Elixir Release

### Building

```bash
# Install dependencies
MIX_ENV=prod mix deps.get

# Build and digest frontend assets
MIX_ENV=prod mix assets.deploy

# Compile the application
MIX_ENV=prod mix compile

# Build the release
MIX_ENV=prod mix release
```

The release is output to `_build/prod/rel/liteskill/`.

### Running

Set the required environment variables and start the server:

```bash
export DATABASE_URL="ecto://user:pass@host/liteskill"
export SECRET_KEY_BASE="your-secret-key-base"
export ENCRYPTION_KEY="your-encryption-key"
export PHX_HOST="your-domain.com"
export PHX_SERVER=true

_build/prod/rel/liteskill/bin/server
```

The `bin/server` script automatically:
1. Runs pending database migrations via `Liteskill.Release.migrate()`
2. Sets `PHX_SERVER=true`
3. Starts the application

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix signing/encryption key (generate with `mix phx.gen.secret`) |
| `ENCRYPTION_KEY` | AES-256-GCM key for secrets at rest (generate with `openssl rand -base64 32`) |
| `PHX_HOST` | Public hostname for the application |
| `PHX_SERVER` | Must be `true` to start the HTTP server (set automatically by `bin/server`) |

See [Environment Variables](../configuration/environment-variables.md) for the complete list.

### Release Scripts

The release includes two helper scripts in the `bin/` directory:

#### `bin/server`

```bash
#!/bin/sh
set -eu
cd -P -- "$(dirname -- "$0")/.."
./bin/liteskill eval "Liteskill.Release.migrate()"
PHX_SERVER=true exec ./bin/liteskill start
```

The primary entrypoint. Runs migrations, then starts the HTTP server. Used by both Docker and bare-metal deployments.

#### `bin/migrate`

```bash
#!/bin/sh
set -eu
cd -P -- "$(dirname -- "$0")/.."
exec ./bin/liteskill eval "Liteskill.Release.migrate()"
```

Runs database migrations only, without starting the server. Useful for CI/CD pipelines or manual migration runs.

### Manual Migration

If you need to run migrations separately (e.g., in a deployment pipeline):

```bash
_build/prod/rel/liteskill/bin/migrate
```

Or using the release eval command directly:

```bash
_build/prod/rel/liteskill/bin/liteskill eval "Liteskill.Release.migrate()"
```

## Docker Deployment

### Using the Dockerfile

The project includes a multi-stage Dockerfile optimized for small image size and fast builds.

**Stage 0 -- Node binary donor:** Copies Node.js from the official Node 24 image.

**Stage 1 -- Build:**
- Based on `hexpm/elixir:1.18.4-erlang-28.3.1-debian-bookworm`
- Installs mix dependencies (prod only)
- Installs npm dependencies for assets
- Compiles the application with `--warnings-as-errors`
- Builds and digests frontend assets
- Creates the Elixir release

**Stage 2 -- Runtime:**
- Based on `debian:bookworm-slim`
- Installs only runtime dependencies (libstdc++, openssl, ncurses, locales, ca-certificates)
- Runs as a non-root `app` user
- Exposes port 4000
- Entrypoint: `bin/server`

### Building the Image

```bash
docker build -t liteskill .
```

### Running the Container

```bash
docker run -d \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/liteskill" \
  -e SECRET_KEY_BASE="your-secret-key-base" \
  -e ENCRYPTION_KEY="your-encryption-key" \
  -e PHX_HOST="your-domain.com" \
  liteskill
```

For a complete setup with PostgreSQL, use [Docker Compose](docker-compose.md).

## SSL / TLS

In production, SSL is enforced by default via the `force_ssl` configuration in `config/prod.exs`:

```elixir
config :liteskill, LiteskillWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: true]
```

This expects a reverse proxy (e.g., nginx, Caddy, AWS ALB) to terminate TLS and set the `X-Forwarded-Proto` header.

To disable SSL enforcement (e.g., for testing or when TLS termination does not set the proto header):

```bash
export FORCE_SSL=false
```

## Health Monitoring

The application binds to `0.0.0.0` (all interfaces) on the configured port. A basic health check can be performed by verifying the HTTP server responds:

```bash
curl -f http://localhost:4000/login
```

## Further Reading

- [Phoenix Deployment Guides](https://hexdocs.pm/phoenix/deployment.html)
- [Elixir Releases](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- [Docker Compose](docker-compose.md)
- [Image Tags](image-tags.md)
