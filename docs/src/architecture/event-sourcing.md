# Event Sourcing

Liteskill uses event sourcing for the chat domain. Conversations are modeled as event streams rather than mutable rows.

## Flow

```
Command → Aggregate → Event → EventStore (append) → PubSub broadcast → Projector → Projection tables
```

1. A context function (e.g. `Chat.send_message/4`) constructs a command tuple
2. `Aggregate.Loader.execute/3` loads the aggregate state by replaying events (or from snapshot), executes the command, and appends resulting events
3. `EventStore.Postgres.append_events/3` inserts events in a transaction with optimistic concurrency (unique index on `stream_id, stream_version`)
4. After successful append, events are broadcast via `Phoenix.PubSub` on topic `"event_store:<stream_id>"`
5. `Chat.Projector` (a GenServer in the supervision tree) subscribes to PubSub and updates projection tables

## EventStore

`Liteskill.EventStore.Postgres` implements the `Liteskill.EventStore` behaviour:

- `append_events(stream_id, expected_version, events_data)` — Append with optimistic concurrency
- `read_stream_forward(stream_id)` — Read all events for a stream
- `stream_version(stream_id)` — Get the current version
- `subscribe(stream_id)` — Subscribe to PubSub notifications
- `save_snapshot/4` and `get_latest_snapshot/1` — Snapshot support for performance

## ConversationAggregate

State machine with states: `:created` → `:active` ↔ `:streaming` → `:archived`

Commands:
- `:create_conversation` — Creates a new conversation
- `:add_user_message` — Adds a user message
- `:start_stream` — Begins LLM streaming
- `:add_chunk` — Appends a streaming chunk
- `:complete_stream` — Marks stream as complete
- `:fail_stream` — Records a stream failure
- `:start_tool_call` / `:complete_tool_call` — Tool calling lifecycle
- `:archive` — Archives the conversation
- `:update_title` — Updates the title
- `:truncate_conversation` — Truncates at a message boundary

## Event Serialization

Events are stored with **string keys** (via `stringify_keys`). Deserialization back to structs happens through `Events.deserialize/1`.

## Stream IDs

Stream IDs follow the format `"conversation-<uuid>"`.

## Projector

`Liteskill.Chat.Projector` is a GenServer that runs in the main supervision tree. It:

- Subscribes to all event store PubSub topics
- Updates the `conversations`, `messages`, `message_chunks`, and `tool_calls` projection tables
- Also supports synchronous `project_events/2` for immediate consistency after writes
