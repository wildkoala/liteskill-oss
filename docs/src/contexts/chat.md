# Chat Context

`Liteskill.Chat` is the primary context for conversation management. It provides write and read APIs backed by event sourcing.

## Boundary

```elixir
use Boundary,
  top_level?: true,
  deps: [Liteskill.Aggregate, Liteskill.Authorization, Liteskill.EventStore, Liteskill.Rbac, Liteskill.LlmModels],
  exports: [Conversation, ConversationAggregate, Events, Message, MessageBuilder, MessageChunk, Projector, StreamRecovery, ToolCall]
```

## Write API

All write operations go through the event sourcing pipeline: command → aggregate → event store → projector.

| Function | Description |
|----------|-------------|
| `create_conversation(params)` | Creates a new conversation with RBAC check |
| `send_message(conversation_id, user_id, content, opts)` | Adds a user message |
| `fork_conversation(conversation_id, user_id, at_message_position)` | Forks at a message boundary |
| `archive_conversation(conversation_id, user_id)` | Archives a conversation |
| `update_title(conversation_id, user_id, title)` | Updates the title |
| `truncate_conversation(conversation_id, user_id, message_id)` | Truncates at a message |
| `edit_message(conversation_id, user_id, message_id, new_content, opts)` | Truncates then re-sends |

## Read API

Read operations query the projection tables directly.

| Function | Description |
|----------|-------------|
| `list_conversations(user_id, opts)` | Lists accessible conversations (paginated, searchable) |
| `count_conversations(user_id, opts)` | Counts accessible conversations |
| `get_conversation(id, user_id)` | Gets a conversation with messages |
| `list_messages(conversation_id, user_id, opts)` | Lists messages (paginated) |
| `get_conversation_tree(conversation_id, user_id)` | Gets fork tree |
| `replay_conversation(conversation_id, user_id)` | Replays aggregate state |

## ACL Management

Delegates to `Liteskill.Authorization`:

- `grant_conversation_access/4` — Grant user access (normalizes "member" to "manager")
- `revoke_conversation_access/3` — Revoke user access
- `leave_conversation/2` — User leaves a shared conversation
- `grant_group_access/4` — Grant group access

## Streaming

- `broadcast_tool_decision/3` — Sends approve/reject decision for pending tool calls
- `recover_stream/2` — Manually recovers a stuck streaming conversation
- `list_stuck_streaming/1` — Finds conversations stuck in streaming state
