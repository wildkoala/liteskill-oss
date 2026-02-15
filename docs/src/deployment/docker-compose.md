# Docker Compose

The simplest way to run Liteskill is with Docker Compose. The provided `docker-compose.yml` defines a PostgreSQL database, the application server, and an optional migration service.

## Services

### `db` -- PostgreSQL

```yaml
db:
  image: pgvector/pgvector:pg16
  restart: unless-stopped
  environment:
    POSTGRES_USER: ${POSTGRES_USER:-liteskill}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-liteskill}
    POSTGRES_DB: ${POSTGRES_DB:-liteskill}
  volumes:
    - pgdata:/var/lib/postgresql/data
  ports:
    - "5432:5432"
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-liteskill}"]
    interval: 5s
    timeout: 5s
    retries: 5
```

Uses the `pgvector/pgvector:pg16` image, which includes PostgreSQL 16 with the pgvector extension pre-installed (required for RAG embeddings). Data is persisted to the `pgdata` volume. A health check ensures the database is ready before the app starts.

### `app` -- Liteskill Application

```yaml
app:
  build: .
  restart: unless-stopped
  depends_on:
    db:
      condition: service_healthy
  ports:
    - "4000:4000"
  environment:
    DATABASE_URL: "ecto://${POSTGRES_USER:-liteskill}:${POSTGRES_PASSWORD:-liteskill}@db/${POSTGRES_DB:-liteskill}"
    SECRET_KEY_BASE: "${SECRET_KEY_BASE}"
    ENCRYPTION_KEY: "${ENCRYPTION_KEY}"
    PHX_HOST: "localhost"
```

Builds from the project Dockerfile and starts the server on port 4000. The `bin/server` entrypoint automatically runs pending migrations before starting the HTTP server. Waits for the database health check to pass before starting.

### `migrate` -- Manual Migrations (Tools Profile)

```yaml
migrate:
  build: .
  command: ["bin/migrate"]
  depends_on:
    db:
      condition: service_healthy
  environment:
    # Same as app
  profiles:
    - tools
```

An optional service under the `tools` profile for running migrations manually. Since `bin/server` runs migrations on boot, this is only needed for offline migration scenarios.

## Quick Start

### 1. Generate Secrets

```bash
# Generate SECRET_KEY_BASE
openssl rand -base64 64

# Generate ENCRYPTION_KEY
openssl rand -base64 32
```

### 2. Create `.env` File

Create a `.env` file in the project root:

```env
POSTGRES_USER=liteskill
POSTGRES_PASSWORD=your-secure-db-password
POSTGRES_DB=liteskill
SECRET_KEY_BASE=your-generated-secret-key-base
ENCRYPTION_KEY=your-generated-encryption-key
AWS_BEARER_TOKEN_BEDROCK=your-bedrock-token
AWS_REGION=us-east-1
```

### 3. Start the Services

```bash
docker compose up
```

This will:
1. Start PostgreSQL and wait for it to be healthy
2. Build the Liteskill Docker image (first time only)
3. Run database migrations automatically
4. Start the web server on `http://localhost:4000`

On first launch, you will be redirected to `/setup` to set the admin password.

### 4. Access the Application

Open `http://localhost:4000` in your browser. Complete the setup wizard to configure the admin password and optionally enable data sources.

## Common Operations

### Stop Services

```bash
# Stop and remove containers (data preserved)
docker compose down

# Stop and remove containers AND volumes (data deleted)
docker compose down -v
```

### Run Migrations Manually

```bash
docker compose run --rm migrate
```

### View Logs

```bash
# All services
docker compose logs -f

# App only
docker compose logs -f app
```

### Rebuild After Code Changes

```bash
docker compose build
docker compose up
```

## OIDC Configuration

To enable SSO via OpenID Connect, uncomment and set the OIDC variables in the `app` service environment:

```yaml
app:
  environment:
    # ... other vars ...
    OIDC_ISSUER: "https://accounts.google.com"
    OIDC_CLIENT_ID: "your-client-id"
    OIDC_CLIENT_SECRET: "your-client-secret"
```

Or add them to your `.env` file:

```env
OIDC_ISSUER=https://accounts.google.com
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
```

## Using a Pre-Built Image

Instead of building from source, you can use a published image from GitHub Container Registry. Replace the `build: .` directive with an `image` reference:

```yaml
app:
  image: ghcr.io/your-org/liteskill:latest
  # ... rest of config unchanged
```

See [Image Tags](image-tags.md) for available tags.

## Volume Persistence

The `pgdata` named volume persists PostgreSQL data across container restarts and rebuilds. To completely reset the database:

```bash
docker compose down -v
docker compose up
```

This removes the volume and recreates the database from scratch on next startup.
