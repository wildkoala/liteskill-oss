# Testing

## Running Tests

```bash
# All tests
mix test

# Single file
mix test test/path_test.exs

# Re-run failures
mix test --failed
```

## Coverage

100% test coverage is required, enforced by ExCoveralls. Files excluded from coverage are listed in `coveralls.json`.

Use `# coveralls-ignore-start` / `# coveralls-ignore-stop` for genuinely unreachable branches (e.g. desktop-only code paths, production-only error handling).

## Test Configuration

### DataCase

```elixir
use Liteskill.DataCase, async: false
```

All database tests use a shared Ecto sandbox (`async: false`).

### Unit Tests

Pure unit tests (aggregates, events, parsers) use:

```elixir
use ExUnit.Case, async: true
```

### Argon2

Test config uses `t_cost: 1, m_cost: 8` for fast password hashing.

## HTTP Mocking with Req.Test

Use `plug: {Req.Test, ModuleName}` to mock HTTP calls:

```elixir
Req.Test.stub(Liteskill.McpServers.Client, fn conn ->
  Req.Test.json(conn, %{"result" => %{"tools" => []}})
end)
```

**Note**: `Req.Test` does NOT trigger `into:` callbacks. Streaming tests require different approaches.

## Projector in Tests

The `Chat.Projector` runs in the main supervision tree. **Never** use `start_supervised!` for it in tests.

## Process Synchronization

Chat context write functions include `Process.sleep(50)` for projector processing. In tests, prefer:

```elixir
_ = :sys.get_state(pid)
```

This is more reliable than additional sleeps.

## Stateful Stubs

For tests that need varying responses across retries, use an `Agent`:

```elixir
{:ok, stub} = Agent.start_link(fn -> [:error, :ok] end)

Req.Test.stub(ModuleName, fn conn ->
  [response | rest] = Agent.get_and_update(stub, fn state ->
    {state, tl(state) ++ [hd(state)]}
  end)
  # use response...
end)
```

Set `backoff_ms: 1` for retry tests to avoid slow tests.

## MCP Client Testing

```elixir
plug: {Req.Test, Liteskill.McpServers.Client}
```
