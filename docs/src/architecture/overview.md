# Architecture Overview

Liteskill is a self-hosted AI chat application built with Elixir/Phoenix. It uses an event-sourced architecture with CQRS (Command Query Responsibility Segregation) to provide a reliable, auditable, and real-time conversational AI experience with support for multi-agent orchestration, RAG (Retrieval-Augmented Generation), and MCP (Model Context Protocol) tool integration.

## High-Level Data Flow

```
                          WRITE PATH
                          =========

  User Action (LiveView)
        |
        v
  Phoenix Context (e.g. Chat)
        |
        v
  Command (tuple)
        |
        v
  Aggregate Loader (execute/3)
        |
        +---> Load aggregate state (snapshot + events replay)
        |
        +---> Handle command --> produce events
        |
        +---> Append events to EventStore (optimistic concurrency)
        |
        v
  EventStore (PostgreSQL, append-only)
        |
        v
  PubSub Broadcast  -----> topic: "event_store:<stream_id>"
        |
        |
        |                 READ PATH
        |                 =========
        v
  Projector (GenServer)
        |
        v
  Projection Tables (conversations, messages, chunks, tool_calls)
        |
        v
  LiveView (PubSub subscription for real-time updates)
        |
        v
  User sees updated UI
```

## Write Path

The write path follows a strict sequence that guarantees consistency:

1. **Command** -- A user action (sending a message, creating a conversation, archiving, etc.) is expressed as a command tuple, e.g. `{:add_user_message, %{content: "Hello"}}`.
2. **Aggregate** -- The `Liteskill.Aggregate.Loader` loads the current aggregate state by replaying events from the event store (with optional snapshot optimization). The aggregate's `handle_command/2` callback validates the command against current state and produces zero or more new events.
3. **EventStore** -- New events are appended to the PostgreSQL-backed event store with optimistic concurrency control. A unique index on `(stream_id, stream_version)` prevents conflicting writes; the loader retries up to 3 times on conflict.
4. **PubSub Broadcast** -- After a successful append, events are broadcast on the Phoenix PubSub topic `"event_store:<stream_id>"`, enabling downstream consumers to react in near real-time.

## Read Path

The read path translates domain events into queryable projection tables:

1. **PubSub** -- The `Liteskill.Chat.Projector` GenServer (running in the main supervision tree) receives event broadcasts.
2. **Projector** -- Each event type is projected into the appropriate read-model tables: `conversations`, `messages`, `message_chunks`, and `tool_calls`. The projector supports both synchronous (`project_events/2`) and asynchronous (`project_events_async/2`) projection, with full replay capability via `rebuild_projections/0`.
3. **Projection Tables** -- Standard Ecto schemas backed by PostgreSQL tables, optimized for the query patterns that the UI and API require.
4. **LiveView UI** -- Phoenix LiveView processes subscribe to PubSub topics for real-time updates. When new events are projected, the UI reflects changes instantly without polling.

## Phoenix Contexts (Bounded Contexts)

The business logic is organized into Phoenix contexts, each representing a bounded context with a clear responsibility:

| Context | Module | Responsibility |
|---------|--------|---------------|
| **Chat** | `Liteskill.Chat` | Conversation CRUD, messaging, forking, streaming orchestration, stream recovery |
| **Accounts** | `Liteskill.Accounts` | User management, dual authentication (OIDC via ueberauth + password via Argon2), invitation system |
| **Authorization** | `Liteskill.Authorization` | Centralized entity ACL system (owner, manager, editor, viewer roles), user-based and group-based access |
| **Groups** | `Liteskill.Groups` | Group management and membership, used for group-based ACL authorization |
| **LLM** | `Liteskill.Llm` | LLM client abstraction, streaming with event store integration, tool calling orchestration, RAG context injection |
| **LLM Providers** | `Liteskill.LlmProviders` | Provider endpoint configurations (API keys, provider types), environment-based provider auto-setup |
| **LLM Models** | `Liteskill.LlmModels` | Model definitions tied to providers, model types (inference, embedding, rerank), cost tracking |
| **MCP Servers** | `Liteskill.McpServers` | MCP server registration, JSON-RPC 2.0 client for `tools/list` and `tools/call` |
| **RAG** | `Liteskill.Rag` | Retrieval-Augmented Generation: collections, sources, documents, chunking, pgvector embeddings, Cohere reranking |
| **Reports** | `Liteskill.Reports` | Report generation, hierarchical sections, threaded comments (user + agent authors) |
| **Agents** | `Liteskill.Agents` | Agent definitions (name, backstory, strategy, system prompt), agent-to-tool assignments via MCP |
| **Teams** | `Liteskill.Teams` | Team definitions as named collections of agents with topology (pipeline, parallel, debate, hierarchical, round_robin) |
| **Runs** | `Liteskill.Runs` | Runtime execution of tasks by agent teams, with run tasks, structured logs, and lifecycle tracking |
| **Schedules** | `Liteskill.Schedules` | Cron-based scheduling for recurring run execution, with ScheduleTick GenServer for due-schedule detection |
| **Data Sources** | `Liteskill.DataSources` | External data source connectors (Google Drive, Wiki), sync workers, content extraction |
| **Usage** | `Liteskill.Usage` | LLM token usage and cost tracking per user, conversation, model, and run |
| **Settings** | `Liteskill.Settings` | Server-wide singleton settings (registration open/closed) |

## Background Jobs (Oban)

Liteskill uses [Oban](https://hexdocs.pm/oban/) for reliable background job processing with PostgreSQL-backed persistence. The queue configuration is:

| Queue | Concurrency | Purpose |
|-------|-------------|---------|
| `default` | 10 | General-purpose jobs |
| `rag_ingest` | 5 | RAG document chunking, embedding generation |
| `data_sync` | 3 | External data source synchronization |
| `agent_runs` | 3 | Agent/team run execution |

## Real-Time Updates

Real-time communication is powered by Phoenix PubSub and LiveView:

- **Event broadcasting**: Every event appended to the event store is broadcast on `"event_store:<stream_id>"`, allowing the projector and any subscribed LiveView processes to react.
- **Tool approval**: The topic `"tool_approval:<stream_id>"` is used for interactive tool-call confirmation flows where the user must approve or deny a tool invocation before it executes.
- **LiveView**: All UI is rendered via Phoenix LiveView, with server-side state management and real-time DOM patching over WebSocket.

## Project Structure

```
lib/
  liteskill/                    # Business logic layer
    aggregate/                  # Event sourcing: aggregate loader
    aggregate.ex                # Aggregate behaviour
    accounts/                   # User, Invitation schemas
    accounts.ex                 # Accounts context
    agents/                     # AgentDefinition, AgentTool, JidoAgent
    agents.ex                   # Agents context
    authorization/              # EntityAcl, Roles
    authorization.ex            # Authorization context
    chat/                       # Conversation, Message, Projector, Events, StreamRecovery
    chat.ex                     # Chat context
    crypto/                     # EncryptedField, EncryptedMap Ecto types
    crypto.ex                   # AES-256-GCM encryption core
    data_sources/               # Source, Document, Connectors, SyncWorker
    data_sources.ex             # DataSources context
    event_store/                # Event, Snapshot schemas, Postgres implementation
    event_store.ex              # EventStore behaviour
    groups/                     # Group, GroupMembership schemas
    groups.ex                   # Groups context
    llm/                        # StreamHandler, RagContext, ToolUtils
    llm.ex                      # LLM context
    llm_models/                 # LlmModel schema
    llm_models.ex               # LlmModels context
    llm_providers/              # LlmProvider schema
    llm_providers.ex            # LlmProviders context
    mcp_servers/                # McpServer schema, Client
    mcp_servers.ex              # McpServers context
    rag/                        # Collection, Source, Document, Chunk, Pipeline, CohereClient
    rag.ex                      # RAG context
    reports/                    # Report, ReportSection, SectionComment
    reports.ex                  # Reports context
    runs/                       # Run, RunTask, RunLog, Runner
    runs.ex                     # Runs context
    schedules/                  # Schedule, ScheduleWorker, ScheduleTick
    schedules.ex                # Schedules context
    settings/                   # ServerSettings schema
    settings.ex                 # Settings context (singleton)
    teams/                      # TeamDefinition, TeamMember
    usage/                      # UsageRecord schema
    application.ex              # OTP Application (supervision tree)
    repo.ex                     # Ecto Repo

  liteskill_web/                # Web layer
    components/                 # Phoenix LiveView components
    controllers/                # Traditional controllers (OAuth callbacks, API)
    live/                       # LiveView modules
    plugs/                      # Auth, RateLimiter, etc.
    router.ex                   # Route definitions
    endpoint.ex                 # Phoenix Endpoint
    telemetry.ex                # Telemetry configuration

priv/
  repo/
    migrations/                 # 43 Ecto migrations
    seeds.exs                   # Database seed data

config/
  config.exs                    # Shared configuration
  dev.exs                       # Development config
  test.exs                      # Test config
  runtime.exs                   # Runtime (production) config
```

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.18, Erlang/OTP 28 |
| Web Framework | Phoenix 1.8.3, LiveView |
| Database | PostgreSQL with pgvector extension |
| Background Jobs | Oban |
| CSS | Tailwind CSS v4 |
| JavaScript | Node 24 (asset build only) |
| Authentication | ueberauth (OIDC), Argon2 (password) |
| Encryption | AES-256-GCM (at-rest field encryption) |
| HTTP Client | Req |
| Tooling | mise (version management) |
