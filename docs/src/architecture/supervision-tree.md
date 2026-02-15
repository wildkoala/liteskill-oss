# OTP Supervision Tree

Liteskill's OTP application is defined in `Liteskill.Application`. The supervision tree uses the `:rest_for_one` strategy and includes infrastructure services, application-level GenServers, background job processing, and the web endpoint.

## Supervision Strategy: `:rest_for_one`

The supervision tree uses `:rest_for_one` rather than `:one_for_one`. With this strategy, if a child process crashes, all children that were started **after** it in the child list are also restarted. This is essential for Liteskill because of lifecycle dependencies between services:

- If **Repo** (database connection pool) crashes and restarts, downstream services like the Projector, StreamRecovery, and Endpoint need to restart too, since they depend on active database connections.
- If **PubSub** crashes and restarts, the Projector must restart to re-establish its PubSub subscriptions.
- If **Oban** crashes, the Endpoint (which may enqueue jobs) benefits from a fresh start after Oban is back.

The ordering of children in the supervision tree is carefully chosen to reflect these dependencies.

## Child Process Order

The children are started in this exact order:

```
Liteskill.Supervisor (:rest_for_one)
  |
  +-- LiteskillWeb.Telemetry             # Telemetry supervisor
  |
  +-- Liteskill.Repo                     # Ecto database connection pool
  |
  +-- DNSCluster                         # DNS-based cluster discovery
  |
  +-- Phoenix.PubSub                     # PubSub message broker
  |
  +-- Oban                               # Background job processor
  |
  +-- Boot Task (non-test only)          # One-time setup tasks
  |     |
  |     +-- Accounts.ensure_admin_user()
  |     +-- LlmProviders.ensure_env_providers()
  |     +-- Settings.get()
  |
  +-- RateLimiter.Sweeper                # ETS bucket cleanup (60s interval)
  |
  +-- Task.Supervisor                    # Named supervisor for async tasks
  |     (name: Liteskill.TaskSupervisor)
  |
  +-- Chat.Projector                     # Event-to-projection GenServer
  |
  +-- Chat.StreamRecovery                # Stuck-stream recovery (2-min sweep)
  |
  +-- Schedules.ScheduleTick             # Schedule due-check (non-test only)
  |
  +-- LiteskillWeb.Endpoint              # Phoenix HTTP/WebSocket endpoint
```

## Component Details

### Core Infrastructure

#### Telemetry (`LiteskillWeb.Telemetry`)

The telemetry supervisor sets up metrics and event handlers for monitoring. It is started first because other components emit telemetry events.

#### Repo (`Liteskill.Repo`)

The Ecto repository manages the PostgreSQL connection pool. Nearly every other component depends on database access, so it is started early in the tree.

#### DNSCluster

Handles DNS-based service discovery for clustering in production deployments. Configured via the `:dns_cluster_query` application environment. Set to `:ignore` when not configured.

#### PubSub (`Phoenix.PubSub`)

The Phoenix PubSub system, named `Liteskill.PubSub`. This is the backbone for real-time event distribution:
- The EventStore broadcasts events after successful appends.
- The Projector could subscribe to receive events (though in practice, projection is called directly by the Chat context).
- LiveView processes subscribe for real-time UI updates.
- Tool approval flows use PubSub for user confirmation.

#### Oban

The background job processor, configured with four queues:

| Queue | Concurrency | Use Case |
|-------|-------------|----------|
| `default` | 10 | General-purpose jobs |
| `rag_ingest` | 5 | RAG document chunking and embedding |
| `data_sync` | 3 | External data source synchronization |
| `agent_runs` | 3 | Agent/team execution runs |

Oban uses PostgreSQL for job persistence, providing at-least-once delivery guarantees and job scheduling.

### Boot Tasks

A one-time `Task` (skipped in the test environment) runs three setup operations immediately after infrastructure is ready:

1. **`Accounts.ensure_admin_user()`** -- Creates the root admin account (`admin@liteskill.local`) if it does not already exist. This ensures there is always a way to access the system after a fresh deployment.

2. **`LlmProviders.ensure_env_providers()`** -- Auto-creates LLM provider records from environment variables. This allows operators to configure providers via environment variables (e.g., for containerized deployments) without manual database setup.

3. **`Settings.get()`** -- Initializes the singleton server settings record if it does not exist. The settings module uses a singleton pattern with a database-enforced unique constraint.

These tasks run before the Projector and Endpoint start, ensuring that the system is in a consistent initial state before it begins accepting requests.

### Pre-Boot Validation

Before the supervision tree starts at all, two critical operations run in the `start/2` function:

1. **`Liteskill.Crypto.validate_key!()`** -- Validates that the `ENCRYPTION_KEY` environment variable is set and can be used to derive a 32-byte AES-256-GCM key. If missing, the application crashes immediately with a clear error message rather than failing later when the first encrypted field is accessed.

2. **`LiteskillWeb.Plugs.RateLimiter.create_table()`** -- Creates the ETS table used by the rate limiter. This must happen before the supervision tree starts because ETS tables are owned by the creating process, and the rate limiter needs the table to exist before any HTTP requests arrive.

### Application Services

#### RateLimiter.Sweeper (`LiteskillWeb.Plugs.RateLimiter.Sweeper`)

A GenServer that periodically (every 60 seconds) sweeps stale rate limiter buckets from the ETS table. This prevents unbounded memory growth from accumulated rate limit entries for clients that are no longer active.

#### Task.Supervisor (`Liteskill.TaskSupervisor`)

A named `Task.Supervisor` used for spawning async work, primarily:
- LLM streaming tasks (the `StreamHandler` spawns tasks here for concurrent streaming).
- Any other fire-and-forget or supervised async operations.

Using a named supervisor (rather than bare `Task.async`) provides:
- Supervision and crash isolation (a failed streaming task does not crash the LiveView).
- Easy identification in observer/debugging tools.

#### Chat.Projector (`Liteskill.Chat.Projector`)

The central event-to-read-model projection GenServer. See [Event Sourcing: Projector](./event-sourcing.md#projector) for full details.

Key points for the supervision tree:
- Must start **after** Repo (needs database access) and PubSub (subscribes to event topics).
- Runs in the main supervision tree -- never use `start_supervised!` in tests.
- If it crashes and restarts (via `:rest_for_one`), it re-establishes its PubSub subscriptions automatically through its `init/1` callback.

#### Chat.StreamRecovery (`Liteskill.Chat.StreamRecovery`)

A GenServer that sweeps for conversations stuck in "streaming" status. Conversations can become orphaned when:
- A streaming `Task` exits normally with an error tuple (no `:DOWN` crash signal).
- The LiveView that spawned the streaming task disconnects before receiving the `:DOWN` message.

**Configuration:**
- Sweep interval: **2 minutes** (`@sweep_interval_ms`)
- Stuck threshold: **5 minutes** (`@threshold_minutes`) -- conversations in "streaming" status for longer than this are considered stuck.

**Recovery process:**
1. Query for conversations with `status = "streaming"` and `updated_at` older than the threshold.
2. For each stuck conversation, call `Chat.recover_stream_by_id/1` to transition it back to "active" status.
3. Log the recovery action.

#### Schedules.ScheduleTick (`Liteskill.Schedules.ScheduleTick`)

A GenServer (skipped in test environment) that periodically checks for schedules whose `next_run_at` has passed. When a due schedule is found, it enqueues an Oban job in the `agent_runs` queue to execute the scheduled run. After enqueuing, it updates the schedule's `last_run_at` and computes the next `next_run_at` from the cron expression.

### Web Endpoint

#### LiteskillWeb.Endpoint

The Phoenix endpoint is the last child started. This is intentional -- the application does not begin serving HTTP requests until all infrastructure and application services are fully initialized. This prevents:
- Users hitting the app before the database is ready.
- Events being broadcast before the Projector is subscribed.
- API requests arriving before boot tasks have completed.

## Lifecycle Example

To illustrate the `:rest_for_one` strategy in action, consider what happens if `Liteskill.Repo` crashes:

1. The Supervisor detects that `Liteskill.Repo` has terminated.
2. `Liteskill.Repo` is restarted (new database connection pool).
3. All children started **after** `Liteskill.Repo` are terminated and restarted in order:
   - `DNSCluster` -- restarts
   - `Phoenix.PubSub` -- restarts (new PubSub node)
   - `Oban` -- restarts (reconnects to job tables)
   - Boot Task -- runs again (idempotent operations)
   - `RateLimiter.Sweeper` -- restarts
   - `Task.Supervisor` -- restarts (running streaming tasks are lost)
   - `Chat.Projector` -- restarts (re-subscribes to PubSub)
   - `Chat.StreamRecovery` -- restarts (reschedules sweep timer)
   - `ScheduleTick` -- restarts (reschedules tick timer)
   - `LiteskillWeb.Endpoint` -- restarts (briefly unavailable, then resumes)

This cascading restart ensures that all downstream services establish fresh connections to the new Repo and PubSub instances.

## Environment-Specific Differences

| Component | Dev/Prod | Test |
|-----------|----------|------|
| Boot Task (ensure_admin, ensure_providers, settings) | Runs | Skipped (`@env != :test`) |
| ScheduleTick | Runs | Skipped (`@env != :test`) |
| All other children | Run | Run |

In the test environment, boot tasks and scheduled ticks are skipped because:
- The test database sandbox does not support concurrent access from boot tasks.
- Scheduled job processing would interfere with deterministic test execution.
