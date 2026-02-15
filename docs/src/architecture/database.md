# Database Design

Liteskill uses PostgreSQL as its sole data store, extended with the pgvector extension for vector similarity search in the RAG subsystem. The database schema serves two distinct purposes: the append-only event log (write model) and the projection tables (read model), along with supporting tables for accounts, authorization, configuration, and more.

## Conventions

### Primary Keys

All tables use **binary UUIDs** for primary keys:

```elixir
@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
```

### Timestamps

All tables use `:utc_datetime` for `inserted_at` and `updated_at` timestamps (where applicable). The event store tables (`events`, `snapshots`) use `:utc_datetime_usec` for microsecond precision.

### String Fields

All string-type columns use Ecto's `:string` type, even for columns that store long text content. The underlying PostgreSQL column types may vary (varchar vs text), but the Ecto schema consistently uses `:string`.

### Foreign Keys

Foreign keys (e.g., `user_id`, `conversation_id`) are set **programmatically** in the context layer, never included in `cast/3` calls. This prevents users from manipulating ownership through form submissions. Example from the Conversation changeset:

```elixir
def changeset(conversation, attrs) do
  conversation
  |> cast(attrs, [:stream_id, :user_id, :title, ...])  # user_id is cast here for internal use
  |> validate_required([:stream_id, :user_id, :status])
  |> foreign_key_constraint(:user_id)
end
```

The `user_id` value is always set by the context function before calling the changeset, never from external input.

---

## Event Sourcing Tables

### events

The append-only event log. This is the source of truth for all conversation state.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Unique event identifier |
| `stream_id` | `string` | NOT NULL | Aggregate stream identifier (e.g., `"conversation-<uuid>"`) |
| `stream_version` | `integer` | NOT NULL | Monotonically increasing version within a stream |
| `event_type` | `string` | NOT NULL | Event type discriminator (e.g., `"ConversationCreated"`) |
| `data` | `map` (JSONB) | NOT NULL | Event payload with string keys |
| `metadata` | `map` (JSONB) | DEFAULT `{}` | Optional metadata |
| `inserted_at` | `utc_datetime_usec` | AUTO | Event creation timestamp |

**Indexes:**
- Unique index on `(stream_id, stream_version)` -- enforces optimistic concurrency

### snapshots

Aggregate state snapshots for performance optimization. Saved every 100 events.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Unique snapshot identifier |
| `stream_id` | `string` | NOT NULL | Aggregate stream identifier |
| `stream_version` | `integer` | NOT NULL | The event version this snapshot captures |
| `snapshot_type` | `string` | NOT NULL | Aggregate type name (e.g., `"ConversationAggregate"`) |
| `data` | `map` (JSONB) | NOT NULL | Serialized aggregate state |
| `inserted_at` | `utc_datetime_usec` | AUTO | Snapshot creation timestamp |

---

## Chat Projection Tables

These tables are the read model, populated by the Projector from domain events.

### conversations

Read-model projection of conversation state.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Conversation identifier |
| `stream_id` | `string` | UNIQUE, NOT NULL | Links to the event stream |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Conversation owner |
| `title` | `string` | | Display title |
| `model_id` | `string` | | LLM model identifier string |
| `system_prompt` | `string` | | Optional system prompt |
| `status` | `string` | DEFAULT `"active"` | One of: `active`, `streaming`, `archived` |
| `llm_model_id` | `binary_id` | FK -> `llm_models.id` | Reference to configured LLM model |
| `parent_conversation_id` | `binary_id` | FK -> `conversations.id` | Parent conversation (if forked) |
| `fork_at_version` | `integer` | | Event version where fork occurred |
| `message_count` | `integer` | DEFAULT `0` | Total messages in conversation |
| `last_message_at` | `utc_datetime` | | Timestamp of most recent message |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### messages

Projection of individual messages within conversations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Message identifier |
| `conversation_id` | `binary_id` | FK -> `conversations.id`, NOT NULL | Parent conversation |
| `role` | `string` | NOT NULL | `"user"` or `"assistant"` |
| `content` | `string` | | Message text content |
| `status` | `string` | DEFAULT `"complete"` | One of: `complete`, `streaming`, `failed` |
| `model_id` | `string` | | LLM model used (assistant messages only) |
| `stop_reason` | `string` | | Why the LLM stopped (e.g., `"end_turn"`, `"error"`) |
| `input_tokens` | `integer` | | Token count for the prompt |
| `output_tokens` | `integer` | | Token count for the response |
| `total_tokens` | `integer` | | Sum of input + output tokens |
| `latency_ms` | `integer` | | Response latency in milliseconds |
| `stream_version` | `integer` | | Event version that created this message |
| `position` | `integer` | NOT NULL | 1-based position within the conversation |
| `rag_sources` | `{:array, :map}` | | Cited RAG sources (filtered after completion) |
| `tool_config` | `map` | | Tool configuration for the message |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### message_chunks

Streaming text chunks for real-time display during LLM response generation.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Chunk identifier |
| `message_id` | `binary_id` | FK -> `messages.id`, NOT NULL | Parent message |
| `chunk_index` | `integer` | NOT NULL | Sequential chunk position |
| `content_block_index` | `integer` | DEFAULT `0` | Content block index (for multi-block responses) |
| `delta_type` | `string` | DEFAULT `"text_delta"` | Type of delta |
| `delta_text` | `string` | | The text content of this chunk |
| `inserted_at` | `utc_datetime` | AUTO | |

### tool_calls

Records of MCP tool invocations within assistant messages.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Tool call identifier |
| `message_id` | `binary_id` | FK -> `messages.id`, NOT NULL | Parent message |
| `tool_use_id` | `string` | NOT NULL | LLM-assigned tool use identifier |
| `tool_name` | `string` | NOT NULL | Name of the tool invoked |
| `input` | `map` | | Tool input parameters (JSON) |
| `output` | `map` | | Tool output result (JSON) |
| `status` | `string` | DEFAULT `"started"` | One of: `started`, `completed` |
| `duration_ms` | `integer` | | Tool execution duration |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

---

## Account & Authorization Tables

### users

User accounts supporting both OIDC and password authentication.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | User identifier |
| `email` | `string` | UNIQUE, NOT NULL | Email address |
| `name` | `string` | | Display name |
| `avatar_url` | `string` | | Profile avatar URL |
| `oidc_sub` | `string` | | OIDC subject identifier |
| `oidc_issuer` | `string` | | OIDC issuer URL |
| `oidc_claims` | `map` | DEFAULT `{}` | Raw OIDC claims |
| `password_hash` | `string` | | Argon2-hashed password |
| `role` | `string` | DEFAULT `"user"` | `"user"` or `"admin"` |
| `force_password_change` | `boolean` | DEFAULT `false` | Requires password change on next login |
| `preferences` | `map` | DEFAULT `{}` | User preferences (e.g., accent color) |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `email`
- Unique index on `(oidc_sub, oidc_issuer)`

### entity_acls

Centralized access control list supporting any entity type with user-based or group-based access.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | ACL entry identifier |
| `entity_type` | `string` | NOT NULL | Entity type being secured |
| `entity_id` | `binary_id` | NOT NULL | ID of the entity being secured |
| `role` | `string` | DEFAULT `"viewer"`, NOT NULL | Access level |
| `user_id` | `binary_id` | FK -> `users.id` | User granted access (mutually exclusive with `group_id`) |
| `group_id` | `binary_id` | FK -> `groups.id` | Group granted access (mutually exclusive with `user_id`) |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Valid entity types:** `agent_definition`, `conversation`, `run`, `llm_model`, `llm_provider`, `mcp_server`, `report`, `schedule`, `source`, `team_definition`, `wiki_space`

**Valid roles:** `owner`, `manager`, `editor`, `viewer`

**Constraints:**
- Check constraint: exactly one of `user_id` or `group_id` must be set
- Unique index on `(entity_type, entity_id, user_id)`
- Unique index on `(entity_type, entity_id, group_id)`

### groups

User groups for group-based authorization.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Group identifier |
| `name` | `string` | NOT NULL | Group name |
| `created_by` | `binary_id` | FK -> `users.id`, NOT NULL | Creator user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### group_memberships

Group membership join table.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Membership identifier |
| `group_id` | `binary_id` | FK -> `groups.id`, NOT NULL | Group |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | User |
| `role` | `string` | DEFAULT `"member"` | `"owner"` or `"member"` |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(group_id, user_id)`

### invitations

Email-based invitation tokens for user registration.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Invitation identifier |
| `email` | `string` | NOT NULL | Invited email address (lowercased) |
| `token` | `string` | NOT NULL | Cryptographic token (32 random bytes, URL-safe base64) |
| `expires_at` | `utc_datetime` | NOT NULL | Expiration time (7 days from creation) |
| `used_at` | `utc_datetime` | | When the invitation was accepted |
| `created_by_id` | `binary_id` | FK -> `users.id` | Admin who created the invitation |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

---

## LLM Configuration Tables

### llm_providers

Provider endpoint configurations with encrypted credentials.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Provider identifier |
| `name` | `string` | NOT NULL | Display name |
| `provider_type` | `string` | NOT NULL | Provider type (validated against supported list) |
| `api_key` | `EncryptedField` | | Encrypted API key |
| `provider_config` | `EncryptedMap` | DEFAULT `{}` | Encrypted provider-specific configuration |
| `instance_wide` | `boolean` | DEFAULT `false` | Available to all users |
| `status` | `string` | DEFAULT `"active"` | `"active"` or `"inactive"` |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(name, user_id)`

### llm_models

Configured LLM models tied to providers.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Model record identifier |
| `name` | `string` | NOT NULL | Display name |
| `model_id` | `string` | NOT NULL | Provider-specific model identifier (e.g., `"claude-sonnet-4-20250514"`) |
| `model_type` | `string` | DEFAULT `"inference"` | `"inference"`, `"embedding"`, or `"rerank"` |
| `model_config` | `EncryptedMap` | DEFAULT `{}` | Encrypted model-specific configuration |
| `instance_wide` | `boolean` | DEFAULT `false` | Available to all users |
| `status` | `string` | DEFAULT `"active"` | `"active"` or `"inactive"` |
| `input_cost_per_million` | `decimal` | | Cost per million input tokens |
| `output_cost_per_million` | `decimal` | | Cost per million output tokens |
| `provider_id` | `binary_id` | FK -> `llm_providers.id`, NOT NULL | Parent provider |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(provider_id, model_id)`

---

## MCP Server Tables

### mcp_servers

Model Context Protocol server registrations with encrypted credentials.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Server identifier |
| `name` | `string` | NOT NULL | Display name |
| `url` | `string` | NOT NULL | HTTPS endpoint URL (SSRF-protected) |
| `api_key` | `EncryptedField` | | Encrypted API key |
| `description` | `string` | | Human-readable description |
| `headers` | `EncryptedMap` | DEFAULT `{}` | Encrypted custom HTTP headers |
| `status` | `string` | DEFAULT `"active"` | `"active"` or `"inactive"` |
| `global` | `boolean` | DEFAULT `false` | Available to all users |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

---

## RAG Tables

### rag_collections

Top-level containers for RAG documents organized by embedding dimensions.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Collection identifier |
| `name` | `string` | NOT NULL | Collection name |
| `description` | `string` | | Description |
| `embedding_dimensions` | `integer` | DEFAULT `1024` | Vector dimensions (256, 384, 512, 768, 1024, or 1536) |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### rag_sources

Sources within a collection, representing the origin of documents.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Source identifier |
| `name` | `string` | NOT NULL | Source name |
| `source_type` | `string` | DEFAULT `"manual"` | `"manual"`, `"upload"`, `"web"`, or `"api"` |
| `metadata` | `map` | DEFAULT `{}` | Source-specific metadata |
| `collection_id` | `binary_id` | FK -> `rag_collections.id`, NOT NULL | Parent collection |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### rag_documents

Documents within a source, containing the raw content to be chunked and embedded.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Document identifier |
| `title` | `string` | NOT NULL | Document title |
| `content` | `string` | | Full document text |
| `metadata` | `map` | DEFAULT `{}` | Document metadata |
| `chunk_count` | `integer` | DEFAULT `0` | Number of chunks generated |
| `status` | `string` | DEFAULT `"pending"` | `"pending"`, `"embedded"`, or `"error"` |
| `content_hash` | `string` | | SHA-256 hash for change detection |
| `source_id` | `binary_id` | FK -> `rag_sources.id`, NOT NULL | Parent source |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### rag_chunks

Individual text chunks with pgvector embeddings for similarity search.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Chunk identifier |
| `content` | `string` | NOT NULL | Chunk text |
| `position` | `integer` | NOT NULL | Position within the document |
| `metadata` | `map` | DEFAULT `{}` | Chunk metadata |
| `token_count` | `integer` | | Estimated token count |
| `content_hash` | `string` | | SHA-256 hash for deduplication |
| `embedding` | `vector` | | pgvector embedding (dimensions match collection setting) |
| `document_id` | `binary_id` | FK -> `rag_documents.id`, NOT NULL | Parent document |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### rag_embedding_requests

Tracking table for embedding and rerank API requests (for monitoring and cost tracking).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Request identifier |
| `request_type` | `string` | NOT NULL | `"embed"` or `"rerank"` |
| `status` | `string` | NOT NULL | `"success"` or `"error"` |
| `latency_ms` | `integer` | | Request latency |
| `input_count` | `integer` | | Number of inputs processed |
| `token_count` | `integer` | | Total tokens processed |
| `model_id` | `string` | | Model used |
| `error_message` | `string` | | Error details (if failed) |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | User who triggered the request |
| `inserted_at` | `utc_datetime` | AUTO | |

---

## Reports Tables

### reports

User-created reports with hierarchical sections.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Report identifier |
| `title` | `string` | NOT NULL | Report title |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### report_sections

Hierarchical sections within a report (supports nesting via `parent_section_id`).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Section identifier |
| `title` | `string` | NOT NULL | Section title |
| `content` | `string` | | Section body content |
| `position` | `integer` | DEFAULT `0` | Ordering position |
| `report_id` | `binary_id` | FK -> `reports.id`, NOT NULL | Parent report |
| `parent_section_id` | `binary_id` | FK -> `report_sections.id` | Parent section (for nesting) |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### section_comments

Threaded comments on report sections, supporting both user and agent authors.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Comment identifier |
| `body` | `string` | NOT NULL | Comment text |
| `author_type` | `string` | NOT NULL | `"user"` or `"agent"` |
| `status` | `string` | DEFAULT `"open"` | `"open"` or `"addressed"` |
| `report_id` | `binary_id` | FK -> `reports.id`, NOT NULL | Parent report |
| `section_id` | `binary_id` | FK -> `report_sections.id` | Section being commented on |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Author (user or on behalf of agent) |
| `parent_comment_id` | `binary_id` | FK -> `section_comments.id` | Parent comment (for threading) |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

---

## Agent Studio Tables

### agent_definitions

Agent "character sheets" defining AI agent behavior and capabilities.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Agent identifier |
| `name` | `string` | NOT NULL | Agent name |
| `description` | `string` | | Description |
| `backstory` | `string` | | Agent backstory/persona |
| `opinions` | `map` | DEFAULT `{}` | Agent opinions/preferences |
| `system_prompt` | `string` | | System prompt for the LLM |
| `strategy` | `string` | DEFAULT `"react"` | `"react"`, `"chain_of_thought"`, `"tree_of_thoughts"`, or `"direct"` |
| `config` | `map` | DEFAULT `{}` | Additional configuration |
| `status` | `string` | DEFAULT `"active"` | `"active"` or `"inactive"` |
| `llm_model_id` | `binary_id` | FK -> `llm_models.id` | LLM model to use |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(name, user_id)`

### agent_tools

Join table linking agent definitions to MCP server tools.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Agent tool assignment identifier |
| `tool_name` | `string` | | Specific tool name (optional, all tools from server if null) |
| `agent_definition_id` | `binary_id` | FK -> `agent_definitions.id`, NOT NULL | Agent |
| `mcp_server_id` | `binary_id` | FK -> `mcp_servers.id`, NOT NULL | MCP server providing the tool |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(agent_definition_id, mcp_server_id, tool_name)`

### team_definitions

Named collections of agents with shared context and default execution topology.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Team identifier |
| `name` | `string` | NOT NULL | Team name |
| `description` | `string` | | Description |
| `shared_context` | `string` | | Shared context provided to all team agents |
| `default_topology` | `string` | DEFAULT `"pipeline"` | Execution topology |
| `aggregation_strategy` | `string` | DEFAULT `"last"` | `"last"`, `"merge"`, or `"vote"` |
| `config` | `map` | DEFAULT `{}` | Additional configuration |
| `status` | `string` | DEFAULT `"active"` | `"active"` or `"inactive"` |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Valid topologies:** `pipeline`, `parallel`, `debate`, `hierarchical`, `round_robin`

**Indexes:**
- Unique index on `(name, user_id)`

### team_members

Join table linking teams to agents with role and position.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Membership identifier |
| `role` | `string` | DEFAULT `"worker"` | Member role within the team |
| `description` | `string` | | Role description |
| `position` | `integer` | DEFAULT `0` | Execution order position |
| `team_definition_id` | `binary_id` | FK -> `team_definitions.id`, NOT NULL | Team |
| `agent_definition_id` | `binary_id` | FK -> `agent_definitions.id`, NOT NULL | Agent |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(team_definition_id, agent_definition_id)`

---

## Run Execution Tables

### runs

Runtime task executions, optionally tied to a team definition.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Run identifier |
| `name` | `string` | NOT NULL | Run name |
| `description` | `string` | | Description |
| `prompt` | `string` | NOT NULL | Task prompt/instructions |
| `topology` | `string` | DEFAULT `"pipeline"` | Execution topology |
| `status` | `string` | DEFAULT `"pending"` | `"pending"`, `"running"`, `"completed"`, `"failed"`, or `"cancelled"` |
| `context` | `map` | DEFAULT `{}` | Run context data |
| `deliverables` | `map` | DEFAULT `{}` | Output deliverables |
| `error` | `string` | | Error message (if failed) |
| `timeout_ms` | `integer` | DEFAULT `1800000` | Timeout (30 minutes) |
| `max_iterations` | `integer` | DEFAULT `50` | Maximum iteration count |
| `started_at` | `utc_datetime` | | Execution start time |
| `completed_at` | `utc_datetime` | | Execution completion time |
| `team_definition_id` | `binary_id` | FK -> `team_definitions.id` | Team executing the run |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | User who initiated the run |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### run_tasks

Individual steps within a run execution.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Task identifier |
| `name` | `string` | NOT NULL | Task name |
| `description` | `string` | | Task description |
| `status` | `string` | DEFAULT `"pending"` | `"pending"`, `"running"`, `"completed"`, `"failed"`, or `"skipped"` |
| `position` | `integer` | DEFAULT `0` | Execution order |
| `input_summary` | `string` | | Summary of task input |
| `output_summary` | `string` | | Summary of task output |
| `error` | `string` | | Error message (if failed) |
| `duration_ms` | `integer` | | Task execution duration |
| `started_at` | `utc_datetime` | | Task start time |
| `completed_at` | `utc_datetime` | | Task completion time |
| `run_id` | `binary_id` | FK -> `runs.id`, NOT NULL | Parent run |
| `agent_definition_id` | `binary_id` | FK -> `agent_definitions.id` | Agent executing this task |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### run_logs

Structured execution logs for debugging and auditing runs.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Log entry identifier |
| `level` | `string` | NOT NULL | `"debug"`, `"info"`, `"warn"`, or `"error"` |
| `step` | `string` | NOT NULL | Step identifier within the run |
| `message` | `string` | NOT NULL | Log message |
| `metadata` | `map` | DEFAULT `{}` | Structured metadata |
| `run_id` | `binary_id` | FK -> `runs.id`, NOT NULL | Parent run |
| `inserted_at` | `utc_datetime` | AUTO | |

---

## Scheduling Tables

### schedules

Cron-based scheduling for recurring run execution.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Schedule identifier |
| `name` | `string` | NOT NULL | Schedule name |
| `description` | `string` | | Description |
| `cron_expression` | `string` | NOT NULL | Cron expression (5 or 6 fields) |
| `timezone` | `string` | DEFAULT `"UTC"` | Timezone for cron evaluation |
| `enabled` | `boolean` | DEFAULT `true` | Whether the schedule is active |
| `status` | `string` | DEFAULT `"active"` | `"active"` or `"inactive"` |
| `prompt` | `string` | NOT NULL | Prompt for scheduled runs |
| `topology` | `string` | DEFAULT `"pipeline"` | Execution topology for created runs |
| `context` | `map` | DEFAULT `{}` | Context passed to created runs |
| `timeout_ms` | `integer` | DEFAULT `1800000` | Timeout for created runs |
| `max_iterations` | `integer` | DEFAULT `50` | Max iterations for created runs |
| `last_run_at` | `utc_datetime` | | Last execution time |
| `next_run_at` | `utc_datetime` | | Next scheduled execution time |
| `team_definition_id` | `binary_id` | FK -> `team_definitions.id` | Team to execute runs |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(name, user_id)`

---

## Data Source Tables

### data_sources

External data source configurations with encrypted metadata.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Source identifier |
| `name` | `string` | NOT NULL | Source name |
| `source_type` | `string` | NOT NULL | Connector type (e.g., `"google_drive"`, `"wiki"`) |
| `description` | `string` | | Description |
| `metadata` | `EncryptedMap` | DEFAULT `{}` | Encrypted connector credentials and config |
| `sync_cursor` | `map` | DEFAULT `{}` | Pagination/sync state |
| `sync_status` | `string` | DEFAULT `"idle"` | `"idle"`, `"syncing"`, `"error"`, or `"complete"` |
| `last_synced_at` | `utc_datetime` | | Last successful sync time |
| `last_sync_error` | `string` (text) | | Last sync error message |
| `sync_document_count` | `integer` | DEFAULT `0` | Number of documents synced |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

### documents (data_source_documents)

Documents synced from external data sources, with hierarchical nesting support.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Document identifier |
| `title` | `string` | NOT NULL | Document title |
| `content` | `string` | | Document content |
| `content_type` | `string` | DEFAULT `"markdown"` | `"markdown"`, `"text"`, or `"html"` |
| `metadata` | `map` | DEFAULT `{}` | Document metadata |
| `source_ref` | `string` | NOT NULL | Reference to the data source |
| `slug` | `string` | | URL-friendly slug (auto-generated from title) |
| `external_id` | `string` | | External system identifier |
| `content_hash` | `string` | | SHA-256 for change detection |
| `parent_document_id` | `binary_id` | FK -> `documents.id` | Parent document (for nesting) |
| `position` | `integer` | DEFAULT `0` | Ordering position |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | Owner user |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Unique index on `(source_ref, slug)`

---

## Usage Tracking Tables

### llm_usage_records

Per-call LLM usage and cost tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Record identifier |
| `message_id` | `binary_id` | | Associated message |
| `model_id` | `string` | NOT NULL | Model identifier string |
| `input_tokens` | `integer` | DEFAULT `0` | Input token count |
| `output_tokens` | `integer` | DEFAULT `0` | Output token count |
| `total_tokens` | `integer` | DEFAULT `0` | Total token count |
| `reasoning_tokens` | `integer` | DEFAULT `0` | Reasoning/thinking token count |
| `cached_tokens` | `integer` | DEFAULT `0` | Cached input token count |
| `cache_creation_tokens` | `integer` | DEFAULT `0` | Cache creation token count |
| `input_cost` | `decimal` | | Computed input cost |
| `output_cost` | `decimal` | | Computed output cost |
| `reasoning_cost` | `decimal` | | Computed reasoning cost |
| `total_cost` | `decimal` | | Total computed cost |
| `latency_ms` | `integer` | | API call latency |
| `call_type` | `string` | NOT NULL | `"stream"` or `"complete"` |
| `tool_round` | `integer` | DEFAULT `0` | Tool calling round number |
| `user_id` | `binary_id` | FK -> `users.id`, NOT NULL | User who made the call |
| `conversation_id` | `binary_id` | FK -> `conversations.id` | Associated conversation |
| `llm_model_id` | `binary_id` | FK -> `llm_models.id` | Associated model record |
| `run_id` | `binary_id` | FK -> `runs.id` | Associated run (for agent calls) |
| `inserted_at` | `utc_datetime` | AUTO | |

**Indexes:**
- Index on `inserted_at` for time-range queries

---

## Settings Tables

### server_settings

Singleton table for server-wide configuration.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Settings identifier |
| `registration_open` | `boolean` | DEFAULT `true` | Whether new user registration is allowed |
| `singleton` | `boolean` | DEFAULT `true` | UNIQUE constraint ensures only one row |
| `inserted_at` | `utc_datetime` | AUTO | |
| `updated_at` | `utc_datetime` | AUTO | |

**Constraints:**
- Unique index on `singleton` (ensures only one row can exist)

---

## Encryption

Liteskill provides transparent field-level encryption for sensitive data at rest using AES-256-GCM.

### EncryptedField (`Liteskill.Crypto.EncryptedField`)

A custom Ecto type for encrypting individual string values. Used for API keys and secrets.

- **Storage format:** Base64-encoded string containing `IV (12 bytes) || tag (16 bytes) || ciphertext`
- **Usage:** `field :api_key, Liteskill.Crypto.EncryptedField`
- **Transparent:** Encryption happens on `dump` (write to DB), decryption on `load` (read from DB)
- **Used by:** `llm_providers.api_key`, `mcp_servers.api_key`

### EncryptedMap (`Liteskill.Crypto.EncryptedMap`)

A custom Ecto type for encrypting JSON maps. Used for complex configuration objects.

- **Storage format:** JSON-encoded map, encrypted with AES-256-GCM, stored as Base64 text
- **Usage:** `field :metadata, Liteskill.Crypto.EncryptedMap, default: %{}`
- **Empty map handling:** `%{}` maps are stored as `NULL` to avoid encrypting empty objects
- **Used by:** `llm_providers.provider_config`, `llm_models.model_config`, `mcp_servers.headers`, `data_sources.metadata`

### Key Management

The encryption key is derived from the `ENCRYPTION_KEY` environment variable (minimum 32 characters) using SHA-256 to produce a fixed 32-byte key. The key is validated at application boot (`Liteskill.Crypto.validate_key!()`) to fail fast if not configured.

---

## Migrations

The database schema is managed through **43 Ecto migrations** (as of the current version), covering the full schema evolution from the initial event store to the latest usage tracking features. Migrations are located in `priv/repo/migrations/` and are timestamped for ordering.

Key migration milestones:
- `20260209003119` -- Initial event store (events, snapshots)
- `20260209003324` -- User accounts
- `20260209003617` -- Chat projection tables
- `20260209014046` -- Groups and memberships
- `20260209140000` -- pgvector extension
- `20260209140001` -- RAG tables
- `20260213010000` -- Centralized entity ACLs
- `20260213100000` -- LLM models (separate from providers)
- `20260214100000` -- Agent studio tables (agents, teams, runs)
- `20260215100000` -- Rename instances to runs
- `20260215200000` -- LLM usage records
