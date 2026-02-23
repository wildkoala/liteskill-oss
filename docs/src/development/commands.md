# Commands

## Development

| Command | Description |
|---------|-------------|
| `mix setup` | Install deps, create DB, run migrations, build assets |
| `mix phx.server` | Start dev server on localhost:4000 |
| `mix ecto.reset` | Drop + create + migrate + seed |
| `iex -S mix phx.server` | Start with interactive shell |

## Testing

| Command | Description |
|---------|-------------|
| `mix test` | Run all tests (auto-creates/migrates DB) |
| `mix test test/path_test.exs` | Run a single test file |
| `mix test --failed` | Re-run previously failed tests |
| `mix coveralls` | Run tests with coverage report |
| `mix coveralls.html` | Generate HTML coverage report |

## Code Quality

| Command | Description |
|---------|-------------|
| `mix precommit` | Full quality check (see below) |
| `mix compile --warnings-as-errors` | Compile with strict warnings |
| `mix format` | Format all Elixir files |
| `mix credo --strict` | Static analysis |
| `mix sobelow --config --exit low` | Security analysis |
| `mix dialyzer` | Type checking |
| `mix deps.unlock --unused` | Remove unused dependency locks |

## Precommit

`mix precommit` runs the full quality pipeline:

1. `compile --warnings-as-errors`
2. `deps.unlock --unused`
3. `format`
4. `credo --strict`
5. `sobelow --config --exit low`
6. `dialyzer`
7. `ecto.create --quiet && ecto.migrate --quiet`
8. `coveralls` (tests with 100% coverage check)
9. `mdbook build docs/`

Always run `mix precommit` after completing changes.

## Docker-Based

| Command | Description |
|---------|-------------|
| `./scripts/test-with-docker.sh test` | Run tests via Docker Postgres |
| `./scripts/test-with-docker.sh precommit` | Full precommit via Docker |

## Desktop

| Command | Description |
|---------|-------------|
| `mix desktop.setup` | Install Tauri dependencies |
| `mix desktop.dev` | Open Tauri dev window |
| `mix desktop.build` | Build desktop release |

## Assets

| Command | Description |
|---------|-------------|
| `mix assets.setup` | Install Tailwind and esbuild |
| `mix assets.build` | Compile + build CSS/JS |
| `mix assets.deploy` | Minified build + digest for production |

## Mise Tasks

| Task | Description |
|------|-------------|
| `mise run singleuser` | Start in single-user mode |
| `mise run local-tauri` | Open Tauri dev window (no sidecar) |
| `mise run linux-appimage` | Build Linux AppImage via Docker |
