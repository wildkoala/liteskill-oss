# Conversations

Liteskill's conversation system provides a real-time AI chat experience built on event sourcing and Phoenix LiveView. Every interaction is persisted as an immutable event, enabling full replay, branching, and audit history.

## Real-Time Streaming Chat

Conversations stream AI responses token-by-token using Phoenix LiveView. When you send a message, the system:

1. Appends a `UserMessageAdded` event to the event store
2. Starts a streaming LLM call via `StreamHandler`
3. Records each text chunk as an `AssistantChunkReceived` event
4. Broadcasts chunks over PubSub for real-time UI updates
5. Finalizes with an `AssistantStreamCompleted` event containing the full response

The streaming infrastructure uses ReqLLM for transport and includes automatic retry with exponential backoff for transient failures (HTTP 429 and 503 responses). The system retries up to 3 times before marking the stream as failed.

## Conversation Lifecycle

Every conversation follows a strict state machine:

```
created --> active <--> streaming --> archived
```

- **created** -- Initial state when the conversation record is first created. Transitions to `active` after the `ConversationCreated` event is applied.
- **active** -- The conversation is idle and ready for new messages. You can send messages, update the title, truncate, fork, or archive from this state.
- **streaming** -- An AI response is being generated. New user messages are blocked during streaming. Tool calls are handled within this state. Transitions back to `active` when the stream completes or fails.
- **archived** -- The conversation is soft-deleted. No further messages, title changes, or streaming can occur. Archived conversations are excluded from the default conversation list.

## Sending Messages and Receiving Responses

To send a message, call `Chat.send_message/4` with the conversation ID, user ID, and content. The function:

1. Authorizes that the user has access to the conversation (owner, direct ACL, or group ACL)
2. Creates a `UserMessageAdded` event via the aggregate
3. Projects the event to the `messages` table
4. Returns the created message record

After sending a message, the LiveView initiates streaming by calling `StreamHandler.handle_stream/3`. The handler:

- Emits an `AssistantStreamStarted` event (transitions to `streaming`)
- Calls the configured LLM model via ReqLLM
- Records each text delta as an `AssistantChunkReceived` event
- On completion, emits `AssistantStreamCompleted` with the full content, token counts, and latency
- On failure, emits `AssistantStreamFailed` with error details

## Conversation Forking

Forking lets you branch a conversation at any message to explore alternate paths. Call `Chat.fork_conversation/3` with a conversation ID, user ID, and the message position to fork at.

The fork operation:

1. Reads all events from the parent conversation's event stream
2. Identifies the stream version corresponding to the target message position
3. Creates a new conversation stream with remapped event data (new conversation ID, new message IDs)
4. Appends a `ConversationForked` event recording the parent stream and fork point
5. Creates an owner ACL for the forking user

Forked conversations are independent from that point forward. The parent conversation is unaffected. You can view the full conversation tree (parent and all descendants) using `Chat.get_conversation_tree/2`.

## Message Editing

Editing a message truncates the conversation at the edited message and re-sends with new content. Internally, `Chat.edit_message/5` calls:

1. `truncate_conversation/3` to remove the target message and everything after it
2. `send_message/4` to add the new content as a fresh user message

This preserves full event history -- the truncation and new message are recorded as separate events. The conversation's aggregate state drops all messages at and after the truncated position.

## Conversation Truncation

You can trim conversation history at any point by calling `Chat.truncate_conversation/3` with a message ID. This:

1. Emits a `ConversationTruncated` event
2. In the aggregate, drops the target message and all messages newer than it
3. Resets the conversation status to `active` and clears any active stream

The truncated messages remain in the event store (events are immutable), but the aggregate state and projections reflect the trimmed history.

## Title Management

Conversations start with a default title of "New Conversation". You can update the title manually via `Chat.update_title/3`, which emits a `ConversationTitleUpdated` event.

The UI also supports auto-generated titles: after the first assistant response, the LiveView can request the LLM to generate a concise title based on the conversation content, then apply it through the same update mechanism.

Title updates work in any non-archived state, including during streaming.

## Archiving Conversations

Archive a conversation with `Chat.archive_conversation/2`. This emits a `ConversationArchived` event and transitions the state to `:archived`. Archived conversations:

- Cannot receive new messages
- Cannot start new streams
- Cannot have their title updated
- Cannot be archived again
- Are excluded from the default `list_conversations/2` query

Bulk archiving is supported via `Chat.bulk_archive_conversations/2`, which archives multiple conversations in a single call.

## Tool Calls During Streaming

When the LLM returns tool use requests during streaming, the system handles them according to the configured mode.

### Auto-Confirm Mode

With `auto_confirm: true`, tools execute automatically without user intervention:

1. The LLM response includes `tool_use` blocks
2. `StreamHandler` validates the tool calls against the allowed tools list
3. For each valid tool call, it emits a `ToolCallStarted` event
4. Executes the tool via the MCP client (or built-in tool handler)
5. Emits a `ToolCallCompleted` event with the result
6. Completes the stream with `stop_reason: "tool_use"`
7. Appends the tool results to the message history and starts a new streaming round

The tool calling loop continues for up to 10 rounds (configurable via `max_tool_rounds`).

### Manual Approval Mode

With `auto_confirm: false` (the default), the UI pauses for user approval:

1. Tool call events are emitted and displayed in the UI
2. The stream handler subscribes to a PubSub topic `"tool_approval:<stream_id>"`
3. The UI presents approve/deny buttons for each pending tool call
4. User decisions are broadcast via `Chat.broadcast_tool_decision/3`
5. Approved tools execute normally; rejected tools record an error result
6. If no decision is received within 300 seconds (5 minutes), all pending tools are automatically rejected

## Sharing Conversations

Conversations support ACL-based sharing with individual users and groups.

### User-Level Sharing

- **Grant access**: `Chat.grant_conversation_access/4` adds a user with a specified role
- **Revoke access**: `Chat.revoke_conversation_access/3` removes a user's access
- **Leave**: `Chat.leave_conversation/2` lets a user remove their own access

Only the conversation owner can grant or revoke access.

### Group-Level Sharing

- **Grant group access**: `Chat.grant_group_access/4` shares with all members of a group

Shared conversations appear in the `list_conversations/2` results for authorized users alongside their own conversations.

### Authorization Model

Access is determined by any of these conditions being true:

1. The user is the conversation owner (`conversation.user_id == user_id`)
2. The user has a direct ACL entry for the conversation
3. The user belongs to a group that has an ACL entry for the conversation

## Stream Recovery

Conversations can become stuck in the `streaming` state when the streaming Task exits without producing a completion or failure event. This happens when:

- The streaming Task exits normally with an error tuple (no crash signal)
- The LiveView that spawned the task disconnects before receiving the `:DOWN` message
- The BEAM node restarts during an active stream

### Automatic Recovery

The `StreamRecovery` GenServer runs in the main supervision tree and performs periodic sweeps:

- **Sweep interval**: Every 2 minutes
- **Stuck threshold**: 5 minutes (conversations in `streaming` state with `updated_at` older than 5 minutes ago)

When stuck conversations are found, `StreamRecovery` calls `Chat.recover_stream_by_id/1` for each one. Recovery:

1. Finds the most recent message in `streaming` status
2. Emits an `AssistantStreamFailed` event with error type `"orphaned_stream"`
3. Projects the event to update the message status to `failed` and the conversation status back to `active`

### Manual Recovery

Users can also trigger recovery manually via `Chat.recover_stream/2`, which performs the same operation with authorization checks and uses error type `"task_crashed"`.
