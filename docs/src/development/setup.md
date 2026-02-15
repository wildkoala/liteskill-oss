# Development Setup

This guide walks through setting up a local development environment for Liteskill.

## Prerequisites

### PostgreSQL with pgvector

Liteskill requires PostgreSQL 16+ with the [pgvector](https://github.com/pgvector/pgvector) extension installed. Options:

- **macOS (Homebrew):** `brew install postgresql@16` then install pgvector
- **Linux:** Install from your distribution's package manager
- **Docker:** `docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres pgvector/pgvector:pg16`

The development database defaults are:
- Host: `localhost`
- Username: `postgres`
- Password: `postgres`
- Database: `liteskill_dev`

### mise (Runtime Manager)

Liteskill uses [mise](https://mise.jdx.dev) to manage language runtimes. Install it from the official site:

```bash
# macOS
brew install mise

# Linux (curl)
curl https://mise.run | sh
```

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd liteskill
```

### 2. Install Runtimes

The `mise.toml` in the project root specifies the required versions:

| Runtime | Version |
|---------|---------|
| Elixir | 1.18 |
| Erlang/OTP | 28 |
| Node.js | 24 |

Install them:

```bash
mise install
```

This downloads and installs the exact versions specified. mise automatically activates them when you enter the project directory.

### 3. Set Up the Project

```bash
mix setup
```

This single command runs:
1. `mix deps.get` -- Installs Elixir dependencies
2. `mix ecto.create` -- Creates the development database
3. `mix ecto.migrate` -- Runs all migrations
4. Asset build steps

### 4. Start the Dev Server

```bash
mix phx.server
```

The application starts at `http://localhost:4000`.

On first visit, you will be redirected to `/setup` to set the admin password and configure initial settings.

## Development Defaults

The development environment (`config/dev.exs`) provides sensible defaults so no environment variables are needed for basic development:

- **Database**: `postgres:postgres@localhost/liteskill_dev`
- **Secret key**: A hardcoded development key
- **Encryption key**: `"dev-only-encryption-key-do-not-use-in-prod"` (for encrypting API keys and secrets)
- **Dev routes**: Enabled (LiveDashboard at `/dev/dashboard`, mailbox at `/dev/mailbox`)
- **Code reloading**: Enabled with file watchers for Elixir, esbuild, and Tailwind
- **Live reload**: Watches templates, controllers, LiveViews, and static assets

## Optional Configuration

### OIDC (Single Sign-On)

To test OIDC authentication locally, set these environment variables before starting the server:

```bash
export OIDC_ISSUER="https://accounts.google.com"
export OIDC_CLIENT_ID="your-client-id"
export OIDC_CLIENT_SECRET="your-client-secret"
mix phx.server
```

### AWS Bedrock

For RAG embedding features that use AWS Bedrock:

```bash
export AWS_BEARER_TOKEN_BEDROCK="your-token"
export AWS_REGION="us-east-1"
```

### LLM Providers

LLM provider API keys are configured through the admin UI at `/admin/providers` after logging in, not through environment variables.

## Useful Dev Tools

- **LiveDashboard**: `http://localhost:4000/dev/dashboard` -- Real-time metrics, process info, and Ecto queries
- **Mailbox Preview**: `http://localhost:4000/dev/mailbox` -- View emails sent in development (Swoosh local adapter)

## Troubleshooting

### Database Connection Errors

Ensure PostgreSQL is running and accessible:

```bash
psql -U postgres -h localhost -c "SELECT 1"
```

### pgvector Extension Missing

If migrations fail due to a missing `vector` type, install the pgvector extension:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Or use the Docker image `pgvector/pgvector:pg16` which includes it.

### Reset Everything

To start fresh with a clean database:

```bash
mix ecto.reset
```

This drops the database, recreates it, runs all migrations, and seeds initial data.
