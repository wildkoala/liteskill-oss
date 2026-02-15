# Runtime Configuration

Liteskill uses Elixir's layered configuration system. Runtime configuration in `config/runtime.exs` reads environment variables and applies them after compilation, making it suitable for secrets and deployment-specific settings.

## Configuration Layering

Configuration files are loaded in this order, with later files overriding earlier ones:

1. **`config/config.exs`** -- Base configuration shared across all environments. Defines defaults for the endpoint, mailer, esbuild, tailwind, Ueberauth, LLM settings, logger, and Oban queues.

2. **`config/dev.exs`** or **`config/test.exs`** or **`config/prod.exs`** -- Environment-specific compile-time configuration, imported at the bottom of `config.exs`.

3. **`config/runtime.exs`** -- Runtime configuration executed after compilation and before the system starts. Reads environment variables for secrets and deployment settings.

## What `runtime.exs` Configures

### HTTP Server

```elixir
if System.get_env("PHX_SERVER") do
  config :liteskill, LiteskillWeb.Endpoint, server: true
end

config :liteskill, LiteskillWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]
```

- `PHX_SERVER=true` enables the HTTP server (required for releases; the `bin/server` script sets this automatically)
- `PORT` configures the listening port (defaults to 4000)

### OIDC Configuration

```elixir
if System.get_env("OIDC_CLIENT_ID") do
  config :ueberauth, Ueberauth.Strategy.OIDCC,
    issuer: System.get_env("OIDC_ISSUER"),
    client_id: System.get_env("OIDC_CLIENT_ID"),
    client_secret: System.get_env("OIDC_CLIENT_SECRET")
end
```

OIDC is only configured when `OIDC_CLIENT_ID` is present. This keeps OIDC entirely optional.

### AWS Bedrock Configuration

```elixir
bedrock_overrides =
  [
    {System.get_env("AWS_BEARER_TOKEN_BEDROCK"), :bedrock_bearer_token},
    {System.get_env("AWS_REGION"), :bedrock_region}
  ]
  |> Enum.reject(fn {val, _key} -> is_nil(val) end)
  |> Enum.map(fn {val, key} -> {key, val} end)

if bedrock_overrides != [] do
  existing = Application.get_env(:liteskill, Liteskill.LLM, [])
  config :liteskill, Liteskill.LLM, Keyword.merge(existing, bedrock_overrides)
end
```

AWS settings are merged into the existing LLM configuration. The base config in `config.exs` sets `bedrock_region: "us-east-1"` as a default.

### Encryption Key

```elixir
if encryption_key = System.get_env("ENCRYPTION_KEY") do
  config :liteskill, :encryption_key, encryption_key
end
```

The encryption key is used by `Liteskill.Crypto` for AES-256-GCM encryption of secrets at rest. See [Encryption](encryption.md) for details.

### Production-Only Configuration

The following settings are only applied when `config_env() == :prod`:

#### Database

```elixir
config :liteskill, Liteskill.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  socket_options: maybe_ipv6
```

- `DATABASE_URL` is required in production (raises on missing)
- `ECTO_IPV6` enables IPv6 socket options
- SSL can be enabled by uncommenting `ssl: true`

#### Endpoint Security

```elixir
config :liteskill, LiteskillWeb.Endpoint,
  url: [host: host, port: 443, scheme: "https"],
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
  secret_key_base: secret_key_base
```

- `SECRET_KEY_BASE` is required in production (raises on missing)
- `PHX_HOST` sets the public hostname (defaults to `example.com`)
- Binds to all interfaces on IPv6 (which also accepts IPv4)

## Environment-Specific Defaults

### Development (`config/dev.exs`)

- Database: `postgres:postgres@localhost/liteskill_dev`
- Secret key: hardcoded development key
- Encryption key: `"dev-only-encryption-key-do-not-use-in-prod"`
- Dev routes enabled (LiveDashboard, mailbox preview)
- Code reloading and live reload enabled
- Debug errors shown

### Test (`config/test.exs`)

- Database: `postgres:postgres@localhost/liteskill_test`
- Secret key: hardcoded test key
- Encryption key: `"test-only-encryption-key-do-not-use-in-prod"`
- Argon2 fast hashing: `t_cost: 1, m_cost: 8`
- Oban in manual testing mode
- Ecto sandbox pool
- Server disabled (port 4002 reserved)
- Settings cache disabled (incompatible with Ecto sandbox)

### Production (`config/prod.exs`)

- Static asset cache manifest enabled
- SSL enforcement via `force_ssl` (disable with `FORCE_SSL=false`)
- Swoosh configured for real email delivery via Req adapter
- Logger level set to `:info`

## Oban Configuration

Background job processing is configured in `config.exs`:

```elixir
config :liteskill, Oban,
  repo: Liteskill.Repo,
  queues: [default: 10, rag_ingest: 5, data_sync: 3, agent_runs: 3]
```

| Queue | Concurrency | Purpose |
|-------|-------------|---------|
| `default` | 10 | General background jobs |
| `rag_ingest` | 5 | RAG document ingestion |
| `data_sync` | 3 | Data source synchronization |
| `agent_runs` | 3 | Agent execution |

In test, Oban uses `testing: :manual` mode for explicit job execution.
