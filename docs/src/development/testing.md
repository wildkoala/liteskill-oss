# Testing

Liteskill maintains 100% code coverage as enforced by ExCoveralls. This page documents testing conventions, patterns, and tools.

## Running Tests

```bash
# Run all tests
mix test

# Run a single test file
mix test test/path_test.exs

# Re-run only previously failed tests
mix test --failed

# Run precommit checks (compile + format + test)
mix precommit
```

The test database is automatically created and migrated when running `mix test`.

## Coverage Requirements

**100% coverage is required.** The project uses [ExCoveralls](https://hex.pm/packages/excoveralls) to enforce this.

### Excluding Unreachable Code

For genuinely unreachable branches (defensive patterns, error clauses that cannot be triggered in practice), use coverage ignore markers:

```elixir
# coveralls-ignore-start
def unreachable_clause do
  # ...
end
# coveralls-ignore-stop
```

Or for single lines:

```elixir
# coveralls-ignore-next-line
_ -> :error
```

### Skip Files

The `coveralls.json` file at the project root lists files excluded from coverage analysis. This includes UI modules (LiveViews, components, layouts), the router, and other files where testing through the browser would be required:

```json
{
  "coverage_options": {
    "minimum_coverage": 100,
    "treat_no_relevant_lines_as_covered": true
  },
  "skip_files": [
    "lib/liteskill_web/components/core_components.ex",
    "lib/liteskill_web/live/chat_live.ex",
    "lib/liteskill_web/live/chat_components.ex",
    ...
  ]
}
```

## Test Configuration

### DataCase

For tests that interact with the database:

```elixir
use Liteskill.DataCase, async: false
```

`DataCase` uses a shared Ecto sandbox (not async) to ensure all tests can see data written by the projector and other processes.

### Unit Tests

For pure logic tests that do not need the database (aggregates, events, parsers):

```elixir
use ExUnit.Case, async: true
```

These can run in parallel for faster test execution.

### Argon2 Configuration

Test config uses fast Argon2 parameters to keep password hashing nearly instant:

```elixir
# config/test.exs
config :argon2_elixir, t_cost: 1, m_cost: 8
```

## HTTP Mocking with Req.Test

All HTTP calls use the [Req](https://hex.pm/packages/req) library. In tests, use `Req.Test` to mock HTTP responses by passing the `plug` option:

```elixir
Req.Test.stub(Liteskill.LLM.BedrockClient, fn conn ->
  Req.Test.json(conn, %{"output" => %{"message" => %{"content" => [%{"text" => "Hello"}]}}})
end)
```

The corresponding production code passes the plug option:

```elixir
Req.new(plug: {Req.Test, Liteskill.LLM.BedrockClient})
```

> **Important:** `Req.Test` does NOT trigger `into:` callbacks. Streaming responses that use `into:` must be tested differently or the `into:` option must be omitted when the test plug is active.

### MCP Client Testing

For MCP server HTTP mocking:

```elixir
Req.Test.stub(Liteskill.McpServers.Client, fn conn ->
  Req.Test.json(conn, %{"result" => %{"tools" => []}})
end)
```

## Projector Considerations

The `Liteskill.Chat.Projector` runs as a GenServer in the main supervision tree. It subscribes to PubSub and updates projection tables (conversations, messages, etc.).

**Never use `start_supervised!` for the projector in tests.** It is already running in the application supervision tree.

### Process Synchronization

Chat context write functions (e.g., `Chat.create_conversation/1`, `Chat.send_message/3`) include a `Process.sleep(50)` to allow the projector time to process events.

In tests, when you need to ensure the projector has finished processing, prefer using `:sys.get_state/1` to synchronize:

```elixir
# After a write operation, synchronize with the projector
_ = :sys.get_state(Liteskill.Chat.Projector)

# Now read operations will see the projected data
conversation = Chat.get_conversation(id, user_id)
```

This is more reliable than additional sleeps and avoids flaky tests.

## Stateful Stubs

For tests that need different responses across multiple calls (e.g., retry behavior), use an `Agent` to maintain state:

```elixir
{:ok, agent} = Agent.start_link(fn -> [:error, :ok] end)

Req.Test.stub(Liteskill.LLM.BedrockClient, fn conn ->
  response = Agent.get_and_update(agent, fn [head | tail] -> {head, tail} end)

  case response do
    :error ->
      conn |> Plug.Conn.send_resp(429, "rate limited")

    :ok ->
      Req.Test.json(conn, %{"output" => %{"message" => %{"content" => [%{"text" => "Hi"}]}}})
  end
end)
```

### Retry Tests

When testing retry behavior, set a minimal backoff to keep tests fast:

```elixir
StreamHandler.converse_stream(conversation_id, user_id, messages,
  backoff_ms: 1
)
```

## Oban Testing

Oban is configured in manual testing mode:

```elixir
# config/test.exs
config :liteskill, Oban, testing: :manual
```

This prevents jobs from running automatically. Use `Oban.Testing` helpers to assert jobs were enqueued and execute them explicitly:

```elixir
assert_enqueued(worker: Liteskill.Workers.IngestWorker)
```

## Settings Cache

The persistent_term-based settings cache is disabled in tests because it is incompatible with the Ecto sandbox:

```elixir
# config/test.exs
config :liteskill, :settings_cache, false
```

## Test File Organization

Tests mirror the `lib/` directory structure:

```
test/
  liteskill/
    chat/              # Chat context tests
    accounts/          # Accounts context tests
    crypto/            # Encryption tests
    aggregate/         # Event sourcing aggregate tests
    ...
  liteskill_web/
    controllers/       # API controller tests
    plugs/             # Plug tests (auth, rate limiter)
    ...
  support/
    data_case.ex       # DataCase helper
    fixtures.ex        # Test data factories
```
