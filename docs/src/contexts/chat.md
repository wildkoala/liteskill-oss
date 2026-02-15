# Chat Context

Module: `Liteskill.Chat`

The Chat context provides write and read APIs for conversations. It follows the event-sourcing architecture:

- **Write path:** Context -> Aggregate -> EventStore -> PubSub -> Projector
- **Read path:** Context -> Ecto queries on projection tables

Stream IDs follow the format `"conversation-<uuid>"`.

## ConversationAggregate State Machine

`Liteskill.Chat.ConversationAggregate`

```
:created --> :active <--> :streaming --> :archived
```

| State | Allowed Commands |
|---|---|
| `:created` | `create_conversation` |
| `:active` | `add_user_message`, `start_assistant_stream`, `update_title`, `archive`, `truncate_conversation` |
| `:streaming` | `receive_chunk`, `complete_stream`, `fail_stream`, `start_tool_call`, `complete_tool_call`, `truncate_conversation` |
| `:archived` | (none -- all commands return errors) |

Aggregate state fields: `conversation_id`, `user_id`, `title`, `model_id`, `system_prompt`, `llm_model_id`, `parent_stream_id`, `fork_at_version`, `status`, `messages`, `current_stream`.

## Event Projection Flow

Events are appended to the EventStore then projected synchronously via `Projector.project_events/2` into the following tables:

- `conversations` -- created, updated, archived
- `messages` -- user messages, assistant stream completions/failures
- `message_chunks` -- individual streaming chunks
- `tool_calls` -- tool call start/complete records

The Projector is a GenServer in the main supervision tree that also subscribes to PubSub for events broadcast by other nodes.

## Write Operations

### `create_conversation(params)`

Creates a new conversation. Auto-generates a conversation ID if not provided. Resolves `llm_model_id` to a `model_id` via `LlmModels.get_model/2`. Executes `ConversationCreated` event, projects it, and auto-creates an owner ACL.

```elixir
create_conversation(%{
  user_id: binary_id,          # required
  title: String.t(),            # default: "New Conversation"
  model_id: String.t(),         # raw model identifier
  llm_model_id: binary_id,     # references LlmModel record
  system_prompt: String.t(),    # optional
  conversation_id: binary_id   # optional, auto-generated if omitted
})
:: {:ok, Conversation.t()} | {:error, term()}
```

### `send_message(conversation_id, user_id, content, opts \\ [])`

Authorizes access, executes `add_user_message` command against the aggregate, projects events, and returns the created message.

```elixir
send_message(binary_id, binary_id, String.t(), keyword())
:: {:ok, Message.t()} | {:error, :not_found | :conversation_archived | :currently_streaming}
```

Options:
- `:tool_config` -- tool configuration map attached to the message

### `fork_conversation(conversation_id, user_id, at_message_position)`

Forks a conversation at the given message position. Reads the parent event stream, finds the stream version corresponding to the message position, copies and remaps events (generating new IDs for messages), appends a `ConversationForked` event, and auto-creates an owner ACL for the forked conversation.

```elixir
fork_conversation(binary_id, binary_id, integer())
:: {:ok, Conversation.t()} | {:error, :not_found}
```

### `archive_conversation(conversation_id, user_id)`

Archives a conversation by executing the `archive` command.

```elixir
archive_conversation(binary_id, binary_id)
:: {:ok, Conversation.t()} | {:error, :not_found | :already_archived}
```

### `bulk_archive_conversations(conversation_ids, user_id)`

Archives multiple conversations. Returns the count of successfully archived conversations.

```elixir
bulk_archive_conversations([binary_id], binary_id)
:: {:ok, integer()}
```

### `update_title(conversation_id, user_id, title)`

Updates the conversation title.

```elixir
update_title(binary_id, binary_id, String.t())
:: {:ok, Conversation.t()} | {:error, :not_found | :conversation_archived}
```

### `truncate_conversation(conversation_id, user_id, message_id)`

Truncates the conversation at the specified message, removing it and all subsequent messages.

```elixir
truncate_conversation(binary_id, binary_id, binary_id)
:: {:ok, Conversation.t()} | {:error, :not_found | :message_not_found | :no_messages}
```

### `edit_message(conversation_id, user_id, message_id, new_content, opts \\ [])`

Truncates at the given message, then sends a new message with the updated content. Effectively replaces a message and everything after it.

```elixir
edit_message(binary_id, binary_id, binary_id, String.t(), keyword())
:: {:ok, Message.t()} | {:error, term()}
```

### `recover_stream(conversation_id, user_id)`

Recovers a conversation stuck in `:streaming` state by failing the streaming message. Requires authorization.

```elixir
recover_stream(binary_id, binary_id)
:: {:ok, Conversation.t()} | {:error, :not_found}
```

### `recover_stream_by_id(conversation_id)`

Recovers a stuck stream without authorization checks. Used by the periodic sweeper (no user context).

```elixir
recover_stream_by_id(binary_id) :: :ok
```

### `broadcast_tool_decision(stream_id, tool_use_id, decision)`

Publishes a tool approval/rejection decision to PubSub on topic `"tool_approval:<stream_id>"`. The StreamHandler listens on this topic when `auto_confirm: false`.

```elixir
broadcast_tool_decision(String.t(), String.t(), :approved | :rejected) :: :ok
```

## ACL Management

These functions delegate to `Liteskill.Authorization` with entity type `"conversation"`.

Note: The `role` parameter `"member"` is normalized to `"manager"` for conversation sharing.

### `grant_conversation_access(conversation_id, grantor_id, grantee_user_id, role \\ "member")`

```elixir
:: {:ok, EntityAcl.t()} | {:error, term()}
```

### `revoke_conversation_access(conversation_id, revoker_id, target_user_id)`

```elixir
:: {:ok, EntityAcl.t()} | {:error, term()}
```

### `leave_conversation(conversation_id, user_id)`

```elixir
:: {:ok, EntityAcl.t()} | {:error, :owner_cannot_leave | :not_found}
```

### `grant_group_access(conversation_id, grantor_id, group_id, role \\ "member")`

```elixir
:: {:ok, EntityAcl.t()} | {:error, term()}
```

## Read Operations

### `list_conversations(user_id, opts \\ [])`

Lists conversations accessible to the user (owned or via ACL). Excludes archived conversations.

```elixir
list_conversations(binary_id, keyword())
:: [Conversation.t()]
```

Options:
- `:limit` -- max results (default: 20)
- `:offset` -- pagination offset (default: 0)
- `:search` -- search term for title (ILIKE match)

### `count_conversations(user_id, opts \\ [])`

Counts accessible conversations. Accepts the same `:search` option as `list_conversations/2`.

```elixir
count_conversations(binary_id, keyword()) :: integer()
```

### `get_conversation(id, user_id)`

Gets a conversation with its messages preloaded (ordered by position ascending). Returns `:not_found` if the conversation does not exist or the user lacks access.

```elixir
get_conversation(binary_id, binary_id)
:: {:ok, Conversation.t()} | {:error, :not_found}
```

### `list_messages(conversation_id, user_id, opts \\ [])`

Lists messages for a conversation ordered by position ascending.

```elixir
list_messages(binary_id, binary_id, keyword())
:: {:ok, [Message.t()]} | {:error, :not_found}
```

Options:
- `:limit` -- max results (default: 100)
- `:offset` -- pagination offset (default: 0)

### `list_stuck_streaming(threshold_minutes \\ 5)`

Returns conversations that have been in `"streaming"` status longer than the specified threshold. Used by the periodic sweeper to detect orphaned streams.

```elixir
list_stuck_streaming(integer()) :: [Conversation.t()]
```

### `get_conversation_tree(conversation_id, user_id)`

Gets a conversation and all its forked descendants. Walks up to the root conversation via `parent_conversation_id`, then returns the root plus all direct descendants.

```elixir
get_conversation_tree(binary_id, binary_id)
:: {:ok, [Conversation.t()]} | {:error, :not_found}
```

### `replay_conversation(conversation_id, user_id)`

Replays all events for a conversation to rebuild the full aggregate state.

```elixir
replay_conversation(binary_id, binary_id)
:: {:ok, ConversationAggregate.t()} | {:error, :not_found}
```

### `replay_from(conversation_id, user_id, from_version)`

Replays events starting from a specific stream version, applying them to a fresh aggregate state.

```elixir
replay_from(binary_id, binary_id, integer())
:: {:ok, ConversationAggregate.t()} | {:error, :not_found}
```

### `update_message_rag_sources(message_id, user_id, rag_sources)`

Updates the RAG sources metadata on an existing message.

```elixir
update_message_rag_sources(binary_id, binary_id, list())
:: {:ok, Message.t()} | {:error, :not_found}
```
