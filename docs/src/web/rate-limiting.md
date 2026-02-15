# Rate Limiting

Liteskill includes a simple ETS-based rate limiter to protect the API against runaway clients or accidental loops. It uses fixed-window counters and is applied to the API pipeline only.

## Overview

Module: `LiteskillWeb.Plugs.RateLimiter`

| Setting | Value |
|---------|-------|
| Algorithm | Fixed-window counter |
| Default limit | 1000 requests per window |
| Default window | 60 seconds |
| Storage | ETS (named table `:liteskill_rate_limiter`) |
| Scope | API pipeline only |

The rate limiter is intentionally generous -- it exists to prevent abuse and accidental loops, not to throttle normal usage.

## How It Works

### Request Counting

Each incoming API request increments a counter in the ETS table:

1. A **key** is derived from the request:
   - Authenticated users: `"user:<user_id>"`
   - Unauthenticated requests: `"ip:<ip_address>"`

2. A **window** number is calculated by dividing the current monotonic time by the window duration (`window_ms`)

3. The counter at `{key, window}` is atomically incremented using `:ets.update_counter/4`

4. If the count exceeds the limit, the request is rejected

### Rate Limit Response

When the limit is exceeded, the plug returns:

```
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 60

{"error": "Too many requests"}
```

The `Retry-After` header value is the window duration in seconds.

### Bucket Format

ETS entries use the format `{{key, window}, count}`:

- **key**: `"user:<uuid>"` or `"ip:<address>"`
- **window**: integer representing the time window (monotonic time divided by `window_ms`)
- **count**: number of requests in this window

The ETS table is created with `read_concurrency: true` and `write_concurrency: true` for minimal contention under concurrent load.

## Stale Entry Sweeper

Module: `LiteskillWeb.Plugs.RateLimiter.Sweeper`

A GenServer that periodically cleans stale rate limiter entries to prevent unbounded memory growth.

| Setting | Value |
|---------|-------|
| Sweep interval | 60 seconds |
| Max entry age | 120 seconds (2 minutes) |

The sweeper runs every 60 seconds and removes all ETS entries where the window number is older than 2 minutes. It uses `:ets.select_delete/2` with a match spec for efficient bulk deletion.

## Configuration

The rate limiter is configured directly in the router pipeline:

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug :fetch_session
  plug LiteskillWeb.Plugs.Auth, :fetch_current_user
  plug LiteskillWeb.Plugs.RateLimiter, limit: 1000, window_ms: 60_000
end
```

Options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:limit` | integer | 1000 | Maximum requests per window |
| `:window_ms` | integer | 60000 | Window duration in milliseconds |

## Initialization

The ETS table is created at application startup via `RateLimiter.create_table/0`, which is called from the application supervisor. The sweeper GenServer is also started in the supervision tree.
