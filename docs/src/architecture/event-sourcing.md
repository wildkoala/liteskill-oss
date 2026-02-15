# Event Sourcing

Liteskill uses a custom-built event sourcing system backed by PostgreSQL. Rather than updating mutable rows in place, every state change is captured as an immutable event appended to an ordered log. The current state of any entity is derived by replaying its event history, with optional snapshots for performance.

This document covers the four core components: the EventStore, the Aggregate system, the ConversationAggregate (the primary domain aggregate), and the Projector.

---

## Event Store

**Module:** `Liteskill.EventStore.Postgres`
**Behaviour:** `Liteskill.EventStore`

The event store is a PostgreSQL-backed append-only log that provides the foundation for all event sourcing in Liteskill. It stores events in an `events` table and provides PubSub-based notification after every successful append.

### Storage Schema

The `events` table has the following structure:

| Column | Type | Description |
|--------|------|-------------|
| `id` | `binary_id` (UUID) | Primary key, auto-generated |
| `stream_id` | `string` | Identifies the aggregate stream (e.g. `"conversation-<uuid>"`) |
| `stream_version` | `integer` | Monotonically increasing version within a stream |
| `event_type` | `string` | Type discriminator (e.g. `"ConversationCreated"`, `"UserMessageAdded"`) |
| `data` | `map` (JSONB) | Event payload, stored with **string keys** |
| `metadata` | `map` (JSONB) | Optional metadata (defaults to `%{}`) |
| `inserted_at` | `utc_datetime_usec` | Auto-generated insertion timestamp |

### Optimistic Concurrency

A unique index on `(stream_id, stream_version)` provides optimistic concurrency control. If two processes try to append events with the same version to the same stream, one will succeed and the other will receive `{:error, :wrong_expected_version}`. This prevents lost updates without pessimistic locking.

The concurrency guarantee works as follows:

1. The caller provides an `expected_version` -- the version of the last event it has seen.
2. New events are assigned versions starting at `expected_version + 1`.
3. If another process has already appended an event at that version, the unique index violation triggers a rollback.
4. The `Ecto.ConstraintError` or `Postgrex.Error` (unique_violation) is caught and translated to `{:error, :wrong_expected_version}`.

### PubSub Broadcasting

After a successful append within the database transaction, events are broadcast via Phoenix PubSub:

```
Topic:   "event_store:<stream_id>"
Message: {:events, stream_id, events}
```

This enables the Projector and any LiveView processes to react to new events in near real-time without polling.

### API

```elixir
# Append events to a stream (within a transaction)
append_events(stream_id, expected_version, events_data)
# Returns {:ok, [%Event{}]} | {:error, :wrong_expected_version}

# Read all events in a stream, ordered by version
read_stream_forward(stream_id)
# Returns [%Event{}]

# Read events from a specific version with a count limit
read_stream_forward(stream_id, from_version, max_count)
# Returns [%Event{}]

# Get the current (maximum) version of a stream
stream_version(stream_id)
# Returns non_neg_integer()

# Subscribe to PubSub events for a stream
subscribe(stream_id)
# Returns :ok
```

### Snapshots

To avoid replaying the full event history on every aggregate load, the event store supports snapshots.

**Schema:** `Liteskill.EventStore.Snapshot`

| Column | Type | Description |
|--------|------|-------------|
| `id` | `binary_id` (UUID) | Primary key, auto-generated |
| `stream_id` | `string` | Stream this snapshot belongs to |
| `stream_version` | `integer` | The event version this snapshot represents |
| `snapshot_type` | `string` | Aggregate type name (e.g. `"ConversationAggregate"`) |
| `data` | `map` (JSONB) | Serialized aggregate state |
| `inserted_at` | `utc_datetime_usec` | Auto-generated insertion timestamp |

**Snapshot API:**

```elixir
# Save a snapshot at a specific version
save_snapshot(stream_id, stream_version, snapshot_type, data)
# Returns {:ok, %Snapshot{}}

# Load the most recent snapshot for a stream
get_latest_snapshot(stream_id)
# Returns {:ok, %Snapshot{}} | {:error, :not_found}
```

Snapshots are saved automatically every **100 events** (configured via `@snapshot_interval` in `Aggregate.Loader`). The snapshot boundary check uses integer division buckets: a snapshot is saved when `div(new_version, 100) > div(old_version, 100)`.

---

## Aggregate System

### Behaviour

**Module:** `Liteskill.Aggregate`

The `Aggregate` behaviour defines the contract for all event-sourced aggregates:

```elixir
@callback init() :: struct()
@callback apply_event(state :: struct(), event :: map()) :: struct()
@callback handle_command(state :: struct(), command :: tuple()) ::
            {:ok, [map()]} | {:error, term()}
```

- `init/0` -- Returns the initial (empty) aggregate state.
- `handle_command/2` -- Validates a command against current state and returns either `{:ok, events}` or `{:error, reason}`. Commands are expressed as tuples: `{:command_name, params_map}`.
- `apply_event/2` -- Applies a single event to the aggregate state, returning the new state. This is used both during replay (loading from the event store) and after appending new events.

### Aggregate Loader

**Module:** `Liteskill.Aggregate.Loader`

The loader is a stateless module that orchestrates the full lifecycle of loading aggregate state and executing commands.

#### Loading State (`load/2`)

```elixir
def load(aggregate_module, stream_id)
# Returns {state, version}
```

The loading process:

1. **Check for snapshot** -- Call `get_latest_snapshot(stream_id)`. If a snapshot exists, deserialize it back into the aggregate struct (converting string keys back to atoms, restoring atom-valued fields like `:status`).
2. **Read events** -- Call `read_stream_forward(stream_id, snapshot_version + 1, 10_000)` to read all events after the snapshot (or from version 1 if no snapshot exists).
3. **Replay events** -- Fold events through `aggregate_module.apply_event/2` to arrive at the current state.
4. **Return** -- Return `{final_state, current_version}`.

#### Executing Commands (`execute/3`)

```elixir
def execute(aggregate_module, stream_id, command)
# Returns {:ok, new_state, stored_events} | {:error, reason}
```

The execution process is atomic with retry:

1. **Load** -- Load the current aggregate state and version.
2. **Handle command** -- Call `aggregate_module.handle_command(state, command)`.
   - If `{:error, reason}`, return the error immediately.
   - If `{:ok, []}` (no events), return the current state unchanged.
   - If `{:ok, events_data}`, proceed to append.
3. **Append** -- Call `append_events(stream_id, version, events_data)`.
   - On success, apply the stored events to get the new state, maybe save a snapshot, and return `{:ok, new_state, stored_events}`.
   - On `{:error, :wrong_expected_version}`, **retry** from step 1 (up to **3 attempts**). This handles the case where another process appended events between load and append.
4. **Snapshot** -- After successful append, if the new version crosses a 100-event boundary, save a snapshot of the new state.

---

## ConversationAggregate

**Module:** `Liteskill.Chat.ConversationAggregate`
**Behaviour:** `Liteskill.Aggregate`
**Stream ID format:** `"conversation-<uuid>"`

The ConversationAggregate is the primary domain aggregate in Liteskill. It models the full lifecycle of a conversation including message exchange, LLM streaming, tool calls, and branching (forking).

### State Machine

```
                 create_conversation
  :created  ========================>  :active
                                          |
                        start_assistant   |   complete_stream
                            _stream       |   fail_stream
                                          v
                                      :streaming
                                          |
                        complete_stream   |   add_user_message
                        fail_stream       |   (after stream completes)
                                          v
                                       :active
                                          |
                          archive         |
                                          v
                                      :archived
```

**Valid states:** `:created`, `:active`, `:streaming`, `:archived`

State transitions and their guards:

| Current State | Command | Next State | Notes |
|---------------|---------|------------|-------|
| `:created` | `create_conversation` | `:active` | Can only be called once |
| `:active` | `add_user_message` | `:active` | Blocked in `:streaming` or `:archived` |
| `:active` | `start_assistant_stream` | `:streaming` | Blocked if already `:streaming` or `:archived` |
| `:streaming` | `receive_chunk` | `:streaming` | Only valid during streaming |
| `:streaming` | `complete_stream` | `:active` | Finalizes the assistant message |
| `:streaming` | `fail_stream` | `:active` | Marks stream as failed, clears current_stream |
| `:streaming` | `start_tool_call` | `:streaming` | Tool calls happen within a stream |
| `:streaming` | `complete_tool_call` | `:streaming` | Marks a tool call as completed |
| any (not archived) | `update_title` | (unchanged) | Updates the conversation title |
| any (not archived) | `archive` | `:archived` | Terminal state |
| `:active` or `:streaming` | `truncate_conversation` | `:active` | Drops messages from a given point forward |

### Aggregate State Struct

```elixir
defstruct [
  :conversation_id,        # UUID of the conversation
  :user_id,                # UUID of the owning user
  :title,                  # Display title
  :model_id,               # LLM model identifier string
  :system_prompt,          # Optional system prompt
  :llm_model_id,           # FK to llm_models table
  :parent_stream_id,       # Stream ID of the parent (if forked)
  :fork_at_version,        # Event version where fork occurred
  status: :created,        # Current state machine status
  messages: [],            # In-memory message list (newest first)
  current_stream: nil      # Active stream metadata (during :streaming)
]
```

The `current_stream` field, when set during `:streaming` state, is a map:

```elixir
%{
  message_id: "uuid",
  model_id: "model-string",
  chunks: [],          # Accumulated text chunks (newest first)
  tool_calls: []       # Tool call records with status
}
```

### Commands

All commands are tuples of the form `{:command_name, params_map}`:

| Command | Required Params | Optional Params |
|---------|----------------|-----------------|
| `{:create_conversation, params}` | `conversation_id`, `user_id`, `title`, `model_id` | `system_prompt`, `llm_model_id` |
| `{:add_user_message, params}` | `content` | `message_id`, `tool_config` |
| `{:start_assistant_stream, params}` | `model_id` | `message_id`, `request_id`, `rag_sources` |
| `{:receive_chunk, params}` | `message_id`, `chunk_index`, `delta_text` | `content_block_index`, `delta_type` |
| `{:complete_stream, params}` | `message_id`, `full_content` | `stop_reason`, `input_tokens`, `output_tokens`, `latency_ms` |
| `{:fail_stream, params}` | `message_id`, `error_type`, `error_message` | `retry_count` |
| `{:start_tool_call, params}` | `message_id`, `tool_use_id`, `tool_name` | `input` |
| `{:complete_tool_call, params}` | `message_id`, `tool_use_id`, `tool_name` | `input`, `output`, `duration_ms` |
| `{:update_title, params}` | `title` | -- |
| `{:archive, params}` | -- | -- |
| `{:truncate_conversation, params}` | `message_id` | -- |

---

## Events

**Module:** `Liteskill.Chat.Events`

There are 12 domain event types, each represented by a dedicated struct module under `Liteskill.Chat.Events.*`:

| Event Type | Struct Module | Description |
|------------|--------------|-------------|
| `ConversationCreated` | `Events.ConversationCreated` | A new conversation was initialized |
| `UserMessageAdded` | `Events.UserMessageAdded` | User sent a message |
| `AssistantStreamStarted` | `Events.AssistantStreamStarted` | LLM streaming response began |
| `AssistantChunkReceived` | `Events.AssistantChunkReceived` | A text chunk arrived during streaming |
| `AssistantStreamCompleted` | `Events.AssistantStreamCompleted` | LLM streaming completed successfully |
| `AssistantStreamFailed` | `Events.AssistantStreamFailed` | LLM streaming failed with an error |
| `ToolCallStarted` | `Events.ToolCallStarted` | An MCP tool invocation began |
| `ToolCallCompleted` | `Events.ToolCallCompleted` | An MCP tool invocation finished |
| `ConversationForked` | `Events.ConversationForked` | A conversation was branched from a parent |
| `ConversationTitleUpdated` | `Events.ConversationTitleUpdated` | The conversation title was changed |
| `ConversationArchived` | `Events.ConversationArchived` | The conversation was archived |
| `ConversationTruncated` | `Events.ConversationTruncated` | Messages were removed from a given point forward |

### Serialization

Events are serialized for storage and deserialized on read:

**`Events.serialize/1`** -- Converts a domain event struct into the event store format:

```elixir
%Events.UserMessageAdded{message_id: "abc", content: "Hello"}
# becomes
%{event_type: "UserMessageAdded", data: %{"message_id" => "abc", "content" => "Hello"}}
```

Key details:
- The struct module is mapped to its string name via a bidirectional registry (`@event_types` / `@event_types_reverse`).
- All map keys in `data` are converted to **strings** via `stringify_keys/1`. This is critical because JSONB storage in PostgreSQL does not preserve atom keys.

**`Events.deserialize/1`** -- Converts an event store record back into a domain struct:

```elixir
%{event_type: "UserMessageAdded", data: %{"message_id" => "abc", "content" => "Hello"}}
# becomes
%Events.UserMessageAdded{message_id: "abc", content: "Hello"}
```

Key details:
- The event type string is looked up in `@event_types` to find the struct module.
- String keys in `data` are converted back to atoms via `String.to_existing_atom/1`.

### Event Data in the Aggregate

When applying events in the `ConversationAggregate`, event data is accessed using **string keys** (e.g., `data["message_id"]`), since events are read directly from the event store where data has been through JSONB serialization.

---

## Stream IDs

All conversation event streams use the format:

```
"conversation-<uuid>"
```

where `<uuid>` is the conversation's binary UUID. This convention is used consistently across the event store, PubSub topics, and aggregate loading.

## PubSub Topics

| Topic Pattern | Message Format | Purpose |
|---------------|---------------|---------|
| `"event_store:<stream_id>"` | `{:events, stream_id, events}` | Event broadcasting after append |
| `"tool_approval:<stream_id>"` | Tool decision messages | User confirmation for tool calls |

---

## Projector

**Module:** `Liteskill.Chat.Projector`

The Projector is a GenServer that translates domain events into read-model projection tables. It is started as part of the main OTP supervision tree (not started in tests via `start_supervised!`).

### Projection Targets

| Event Type | Target Table(s) | Operation |
|------------|-----------------|-----------|
| `ConversationCreated` | `conversations` | Insert new conversation row |
| `UserMessageAdded` | `messages`, `conversations` | Insert message, increment `message_count`, update `last_message_at` |
| `AssistantStreamStarted` | `messages`, `conversations` | Insert streaming message (status: "streaming"), update conversation status to "streaming" |
| `AssistantChunkReceived` | `message_chunks` | Insert chunk record |
| `AssistantStreamCompleted` | `messages`, `conversations` | Update message with full content, tokens, latency; set status to "complete"; filter cited RAG sources; reset conversation to "active" |
| `AssistantStreamFailed` | `messages`, `conversations` | Mark message as "failed", reset conversation to "active" |
| `ToolCallStarted` | `tool_calls` | Insert tool call record (status: "started") |
| `ToolCallCompleted` | `tool_calls` | Update tool call with output, duration, status: "completed" |
| `ConversationForked` | `conversations` | Set `parent_conversation_id` and `fork_at_version` |
| `ConversationTitleUpdated` | `conversations` | Update title |
| `ConversationArchived` | `conversations` | Set status to "archived" |
| `ConversationTruncated` | `messages`, `conversations` | Delete target message and all subsequent messages, update `message_count` |

### API

```elixir
# Synchronous projection -- blocks until events are projected
project_events(stream_id, events)
# Returns :ok

# Asynchronous projection -- returns immediately (used for streaming chunks)
project_events_async(stream_id, events)
# Returns :ok

# Full rebuild -- deletes all projections and replays all events
rebuild_projections()
# Returns {:ok, _}
```

### Error Handling

Each event is projected individually within a try/rescue block. If a single event projection fails:

1. The error is logged with stream ID, event type, and version.
2. A telemetry event `[:liteskill, :projector, :event_failed]` is emitted with error metadata.
3. Processing continues with the next event -- a single bad event does not halt the projector.

If a conversation lookup fails (the conversation row does not exist for the given `stream_id`):

1. A warning is logged.
2. A telemetry event `[:liteskill, :projector, :conversation_not_found]` is emitted.
3. The event is skipped.

### RAG Source Filtering

When projecting `AssistantStreamCompleted`, the projector filters RAG sources to only include those that were actually cited in the response. It scans the full content for `[uuid:<uuid>]` patterns and retains only sources whose `document_id` matches a cited UUID. If no sources were cited, `rag_sources` is set to `nil`.
