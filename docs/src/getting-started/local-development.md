# Local Development

## Quick Start

```bash
# Install tool versions
mise install

# Install deps, create DB, run migrations, build assets
mix setup

# Start the dev server
mix phx.server
```

The app will be available at [http://localhost:4000](http://localhost:4000).

## Without Local Postgres

If you don't have PostgreSQL installed locally, use the Docker-based scripts:

```bash
# Run tests with a temporary Docker Postgres
./scripts/test-with-docker.sh test

# Full precommit with Docker Postgres
./scripts/test-with-docker.sh precommit
```

## Single-User Mode

For desktop or self-hosted single-user setups:

```bash
SINGLE_USER_MODE=true mix phx.server
```

Or use the mise task:

```bash
mise run singleuser
```

This skips the login screen and auto-provisions an admin user.

## Desktop Mode

Liteskill can run as a desktop application via Tauri (ex_tauri):

```bash
mix desktop.setup   # Install Tauri dependencies
mix desktop.dev     # Open Tauri dev window
```

Desktop mode bundles PostgreSQL, runs in single-user mode, and stores data in platform-specific directories (e.g. `~/Library/Application Support/Liteskill` on macOS).
