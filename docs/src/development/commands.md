# Mix Commands

Reference for the most commonly used Mix commands in the Liteskill project.

## Development Commands

| Command | Description |
|---------|-------------|
| `mix setup` | Install dependencies, create database, run migrations, and build assets. Run this after cloning the repository. |
| `mix phx.server` | Start the development server on `http://localhost:4000` with code reloading and live reload enabled. |
| `mix ecto.reset` | Drop the database, recreate it, run all migrations, and seed initial data. Useful for starting fresh. |

## Testing Commands

| Command | Description |
|---------|-------------|
| `mix test` | Run all tests. Automatically creates and migrates the test database if needed. |
| `mix test test/path_test.exs` | Run a single test file. |
| `mix test --failed` | Re-run only tests that failed in the previous run. |
| `mix precommit` | Run the full precommit suite: compile with warnings-as-errors, remove unused dependency locks, check formatting, and run all tests. **Always run this after completing changes.** |

## Database Commands

| Command | Description |
|---------|-------------|
| `mix ecto.create` | Create the database. |
| `mix ecto.migrate` | Run pending migrations. |
| `mix ecto.rollback` | Roll back the last migration. |
| `mix ecto.reset` | Drop + create + migrate + seed. |
| `mix ecto.gen.migration <name>` | Generate a new migration file. |

## Asset Commands

| Command | Description |
|---------|-------------|
| `mix assets.deploy` | Build and digest production assets (CSS via Tailwind, JS via esbuild). |
| `mix assets.setup` | Install esbuild and Tailwind binaries. |

## Release Commands

| Command | Description |
|---------|-------------|
| `mix release` | Build a production release to `_build/prod/rel/liteskill/`. |
| `mix phx.gen.secret` | Generate a random secret key base for production use. |

## Precommit Details

The `mix precommit` task runs the following steps in sequence:

1. **`mix compile --warnings-as-errors`** -- Ensures no compiler warnings exist
2. **`mix deps.unlock --unused`** -- Removes unused dependencies from the lock file
3. **`mix format`** -- Formats all Elixir source files
4. **`mix test`** -- Runs the full test suite with coverage

If any step fails, the command exits with a non-zero status. This is the recommended command to run before pushing changes:

```bash
mix precommit
```

## Coverage Commands

| Command | Description |
|---------|-------------|
| `mix coveralls` | Run tests with coverage summary output. |
| `mix coveralls.html` | Run tests and generate an HTML coverage report in `cover/`. |
| `mix coveralls.detail` | Run tests with detailed per-file coverage output. |

These commands automatically run in the `:test` environment.
