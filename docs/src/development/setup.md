# Development Setup

## Prerequisites

1. Install [mise](https://mise.jdx.dev/)
2. Clone the repository
3. Run `mise install` to get Elixir 1.18, Erlang/OTP 28, and Node.js 24

## Setup

```bash
mix setup
```

This runs:
1. `deps.get` — Install Elixir dependencies
2. `ecto.create` — Create the database
3. `ecto.migrate` — Run migrations
4. `run priv/repo/seeds.exs` — Seed data
5. `npm install --prefix assets` — Install Node dependencies
6. `tailwind.install --if-missing` — Install Tailwind
7. `esbuild.install --if-missing` — Install esbuild
8. `gen.jr_prompt` — Generate JSON render prompt
9. Compile and build assets

## Database Reset

```bash
mix ecto.reset
```

Drops, creates, migrates, and seeds the database.

## Running the Server

```bash
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

## Docker-Based Development

If you don't have PostgreSQL installed locally:

```bash
# Run tests with Docker Postgres
./scripts/test-with-docker.sh test

# Full precommit
./scripts/test-with-docker.sh precommit
```

## Docker Compose (Production-like)

```bash
# Generate secrets
export SECRET_KEY_BASE=$(openssl rand -base64 64)
export ENCRYPTION_KEY=$(openssl rand -base64 32)

# Start
docker compose up -d

# Run migrations
docker compose run --rm -e PROFILE=tools migrate
```
