# Local Development

This guide walks you through setting up Liteskill for local development from a fresh clone.

## 1. Clone the Repository

```bash
git clone https://github.com/liteskill/liteskill-oss.git
cd liteskill-oss
```

## 2. Install Tool Versions

With [mise](https://mise.jdx.dev/) installed (see [Prerequisites](prerequisites.md)), install the pinned versions of Elixir, Erlang, and Node:

```bash
mise install
```

This reads `mise.toml` and installs Elixir 1.18, Erlang 28, and Node 24. The first run may take several minutes if Erlang needs to be compiled from source.

Verify the versions are active:

```bash
mise exec -- elixir --version
mise exec -- erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().'
mise exec -- node --version
```

> **Tip:** If you have mise shell integration configured (via `mise activate`), you can drop the `mise exec --` prefix and run `elixir`, `mix`, etc. directly inside the project directory.

## 3. Run the Setup Task

The `mix setup` alias installs all dependencies, creates the database, runs migrations, seeds initial data, and builds frontend assets in a single command:

```bash
mise exec -- mix setup
```

This runs the following steps in order:

1. `mix deps.get` -- Fetch Elixir dependencies
2. `mix ecto.create` -- Create the PostgreSQL database (`liteskill_dev`)
3. `mix ecto.migrate` -- Run all database migrations (including pgvector extension setup)
4. `mix run priv/repo/seeds.exs` -- Seed initial data
5. `npm install --prefix assets` -- Install Node.js dependencies for the asset pipeline
6. `mix assets.setup` -- Install Tailwind CSS and esbuild binaries
7. `mix assets.build` -- Compile, build Tailwind CSS, and bundle JavaScript

> **Note:** If setup fails on the database step, make sure PostgreSQL is running and accepts the default credentials (`postgres`/`postgres` on `localhost:5432`). See [Prerequisites](prerequisites.md) for database configuration details.

## 4. Start the Development Server

```bash
mise exec -- mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) in your browser.

The development server includes:

- **Live reload** -- Changes to `.ex`, `.heex`, `.js`, and `.css` files trigger automatic browser refresh
- **Debug annotations** -- LiveView renders include source location annotations for easier debugging
- **Web console logger** -- Server log messages are forwarded to the browser console
- **LiveDashboard** -- Available at [http://localhost:4000/dev/dashboard](http://localhost:4000/dev/dashboard) for inspecting processes, metrics, and Ecto queries
- **Swoosh mailbox** -- Email previews at [http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox)

## 5. Environment Variables

### Development Defaults

In development mode, most configuration is hardcoded in `config/dev.exs` so you can start working without setting any environment variables. The notable defaults are:

| Setting | Default | Source |
|---------|---------|--------|
| Database host | `localhost` | `config/dev.exs` |
| Database name | `liteskill_dev` | `config/dev.exs` |
| Database user/password | `postgres` / `postgres` | `config/dev.exs` |
| HTTP port | `4000` | `config/runtime.exs` (via `PORT` env var, defaults to `4000`) |
| Secret key base | Hardcoded dev-only value | `config/dev.exs` |
| Encryption key | `dev-only-encryption-key-do-not-use-in-prod` | `config/dev.exs` |

> **Important:** The `SECRET_KEY_BASE` and `ENCRYPTION_KEY` values in `config/dev.exs` are for local development only. Never use them in production. See the [Docker](docker.md) guide or the environment variables reference for production configuration.

### Optional Environment Variables

You can override any of these in development by setting environment variables before starting the server:

| Variable | Description |
|----------|-------------|
| `PORT` | HTTP port (default: `4000`) |
| `OIDC_ISSUER` | OpenID Connect issuer URL (enables SSO login) |
| `OIDC_CLIENT_ID` | OIDC client ID |
| `OIDC_CLIENT_SECRET` | OIDC client secret |
| `AWS_BEARER_TOKEN_BEDROCK` | AWS Bedrock bearer token (only needed for legacy Bedrock RAG embeddings) |
| `AWS_REGION` | AWS region for Bedrock (only needed for legacy Bedrock RAG embeddings) |

LLM provider credentials (API keys, endpoints, regions) are configured through the admin UI after first login, not through environment variables.

## 6. Common Development Commands

```bash
# Run the full pre-commit suite (compile with warnings-as-errors, format, test)
mise exec -- mix precommit

# Run all tests
mise exec -- mix test

# Run a single test file
mise exec -- mix test test/liteskill/chat_test.exs

# Re-run previously failed tests
mise exec -- mix test --failed

# Reset the database (drop, create, migrate, seed)
mise exec -- mix ecto.reset

# Open an interactive Elixir shell with the application loaded
mise exec -- iex -S mix
```

## 7. What Happens on Boot

When the application starts (whether via `mix phx.server` or `iex -S mix`), the following happens automatically:

1. The **admin user** (`admin@liteskill.local`) is created if it does not already exist. This user is guaranteed to have the `admin` role.
2. The **Projector** GenServer starts and subscribes to PubSub for event store changes.
3. The **Oban** job processor starts for background tasks (URL ingestion, agent runs, etc.).
4. The **HTTP server** begins listening on the configured port.

The admin user created on boot has no password set initially. See [First Run](first-run.md) for the setup wizard that guides you through initial configuration.
