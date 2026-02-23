# Architecture Overview

Liteskill is an event-sourced Phoenix application organized around bounded contexts with enforced boundaries (via the `boundary` library).

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    LiteSkillWeb                         │
│  LiveView UI │ REST API │ Auth Plugs │ Rate Limiting    │
└──────────┬──────────────┬───────────────────────────────┘
           │              │
┌──────────▼──────────────▼───────────────────────────────┐
│                   Context Layer                          │
│  Chat │ Accounts │ Authorization │ Groups │ LLM │ ...   │
└──────────┬──────────────────────────────────────────────┘
           │
┌──────────▼──────────────────────────────────────────────┐
│              Infrastructure Layer                        │
│  EventStore │ Aggregate │ Crypto │ Repo │ PubSub        │
└─────────────────────────────────────────────────────────┘
```

## Bounded Contexts

Each context is a top-level `Boundary` module that declares its dependencies and exports:

| Context | Responsibility |
|---------|---------------|
| `Liteskill.Chat` | Conversations, messages, streaming, tool calls |
| `Liteskill.Accounts` | Users, OIDC, password auth, invitations |
| `Liteskill.Authorization` | Entity ACLs, role hierarchy, access queries |
| `Liteskill.Groups` | Group management and memberships |
| `Liteskill.LLM` | LLM completions, stream orchestration |
| `Liteskill.LlmProviders` | Provider CRUD, env bootstrapping |
| `Liteskill.LlmModels` | Model CRUD, provider options |
| `Liteskill.McpServers` | MCP server CRUD, tool selection |
| `Liteskill.Rag` | Collections, sources, documents, embeddings, search |
| `Liteskill.Agents` | Agent definitions, tool/source ACLs |
| `Liteskill.Teams` | Team definitions with agent composition |
| `Liteskill.Runs` | Run execution, tasks, logs |
| `Liteskill.Reports` | Reports with nested sections and comments |
| `Liteskill.Schedules` | Cron-based recurring runs |
| `Liteskill.DataSources` | External data connectors (Google Drive, Confluence, etc.) |
| `Liteskill.Usage` | Token/cost tracking and aggregation |
| `Liteskill.Crypto` | AES-256-GCM encryption at rest |
| `Liteskill.Rbac` | Role-based permission checks |

## Key Design Decisions

- **Event sourcing for chat**: Conversations are append-only event streams, enabling forking, replay, and audit trails.
- **Projection tables**: Read-side tables (`conversations`, `messages`, `message_chunks`, `tool_calls`) are populated by a `Projector` GenServer for efficient querying.
- **ACL-based authorization**: A single `entity_acls` table handles access control for all entity types (conversations, reports, wiki spaces, MCP servers, agents, etc.).
- **Binary UUIDs**: All primary keys are binary UUIDs.
- **Req only**: All HTTP is done via the Req library — no httpoison, tesla, or httpc.
