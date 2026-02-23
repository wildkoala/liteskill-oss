# Database

Liteskill uses PostgreSQL 16 with the **pgvector** extension for vector similarity search.

## Conventions

- **Binary UUIDs** for all primary keys
- **`:utc_datetime`** for all timestamps
- All schemas use `field :name, :string` even for text columns
- Foreign keys (e.g. `user_id`) are set programmatically, never in `cast`
- Custom Postgrex types registered via `Liteskill.Repo.PostgrexTypes`

## Key Tables

### Event Store
- `events` — Append-only event log with `(stream_id, stream_version)` unique index
- `snapshots` — Aggregate snapshots for performance

### Projections (Chat)
- `conversations` — Current conversation state
- `messages` — Projected messages
- `message_chunks` — Streaming chunks
- `tool_calls` — Tool call records

### Accounts & Auth
- `users` — User records (OIDC and password auth)
- `invitations` — Admin-created invite tokens
- `entity_acls` — Unified ACL table for all entity types
- `rbac_roles` / `rbac_role_permissions` / `rbac_user_roles` — Role-based access control

### LLM
- `llm_providers` — Provider configurations (API keys, regions, types)
- `llm_models` — Model definitions linked to providers
- `usage_records` — Token/cost tracking per API call

### RAG
- `rag_collections` — Top-level grouping for embeddings
- `rag_sources` — Sources within collections
- `rag_documents` — Documents to be chunked and embedded
- `rag_chunks` — Chunked text with pgvector embeddings
- `embedding_requests` — Embedding API call logs

### Data Sources
- `data_sources` — External connectors (Google Drive, Confluence, Jira, GitHub, GitLab, SharePoint)
- `data_source_documents` — Documents synced from connectors

### Features
- `reports` / `report_sections` / `section_comments` — Structured report documents
- `agent_definitions` — AI agent configurations
- `team_definitions` — Agent team compositions
- `runs` / `run_logs` / `run_tasks` — Agent execution tracking
- `schedules` — Cron-based recurring run definitions
- `mcp_servers` — MCP server registrations
- `user_tool_selections` — Per-user MCP server selection state
- `groups` / `group_memberships` — User groups

## pgvector

The `rag_chunks` table stores vector embeddings using the pgvector extension. Similarity search uses the `<=>` (cosine distance) operator.
