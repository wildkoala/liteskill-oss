# Introduction

Liteskill is a self-hosted AI chat application built with Elixir and Phoenix 1.8.3. It gives teams a private, auditable platform for working with large language models -- without sending data to third-party SaaS products you don't control. Deploy it on your own infrastructure, connect your preferred LLM providers, and retain full ownership of every conversation, document, and audit record.

## Key Features

- **56+ LLM providers via ReqLLM** -- Configure OpenAI, Anthropic, AWS Bedrock, Google, Groq, Azure, Cerebras, xAI, DeepSeek, vLLM, OpenRouter, and dozens more through the admin UI. Custom base URL override for proxies like LiteLLM.
- **Real-time streaming via LiveView** -- Token-by-token responses delivered over WebSocket with no polling. The UI updates as the model generates, backed by Phoenix LiveView for a seamless single-page experience.
- **MCP tool support** -- Connect external Model Context Protocol servers so the AI can call APIs, query databases, execute code, and interact with external systems. Supports both automatic execution and manual approval workflows.
- **Conversation forking** -- Branch any conversation at any message to explore alternate paths, compare model responses, or try different prompts without losing the original thread.
- **Event sourcing with full audit trail** -- Every state change is recorded as an immutable event in an append-only store. You get a complete history of what happened, when, and why -- with the ability to replay or rebuild state at any point.
- **RAG with pgvector** -- Organize knowledge into collections, embed documents with configurable models, and search with pgvector cosine similarity. Ingest URLs asynchronously via Oban background jobs with automatic chunking and embedding.
- **Structured reports with nested sections** -- Create documents with infinitely-nesting sections, collaborative comments with replies, resolution workflows, ACL sharing, and markdown rendering. Reports serve as deliverables for agent pipeline runs.
- **Agent Studio for multi-agent pipelines** -- Define AI agents with strategies (ReAct, chain-of-thought, tree-of-thoughts, direct), backstories, and opinions. Assemble agents into ordered teams and execute pipeline runs that produce structured report deliverables.
- **Dual authentication (OIDC + password)** -- Supports OpenID Connect for enterprise SSO and password-based registration for standalone deployments. Both methods coexist, so you can mix authentication strategies.
- **ACL-based access control** -- Share conversations, reports, groups, agents, teams, and runs with specific users or groups. Owner and member roles control who can view, edit, or manage access.
- **Encrypted secrets (AES-256-GCM)** -- API keys, MCP credentials, and provider configurations are encrypted at rest. Encryption keys are managed outside the database so a database breach alone does not expose secrets.

## Tech Stack

| Component | Version / Details |
|-----------|-------------------|
| **Elixir** | 1.18 |
| **Erlang/OTP** | 28 |
| **Phoenix** | 1.8.3 |
| **Phoenix LiveView** | 1.1.x |
| **PostgreSQL** | 14+ with pgvector extension |
| **Tailwind CSS** | v4 (no `tailwind.config.js` -- uses `@import "tailwindcss"` syntax) |
| **Oban** | Background job processing for URL ingestion, agent runs, and scheduled tasks |
| **ReqLLM** | HTTP-based LLM client supporting 56+ providers |
| **Req** | HTTP client (used everywhere -- no httpoison, tesla, or httpc) |
| **Bandit** | HTTP server |
| **Ueberauth + OIDCC** | OpenID Connect authentication |
| **Argon2** | Password hashing |
| **Jido** | Agent orchestration framework |

Tool versions are pinned in `mise.toml` at the repository root and managed by [mise](https://mise.jdx.dev/).

## Architecture at a Glance

Liteskill uses event sourcing with CQRS. The write path flows through aggregates and an append-only event store; the read path queries projection tables maintained by a GenServer projector that subscribes to PubSub:

```
Command -> Aggregate -> EventStore (append) -> PubSub -> Projector -> Projection Tables
                                                        -> LiveView (real-time UI updates)
```

The `ConversationAggregate` enforces a state machine -- **created -> active <-> streaming -> archived** -- ensuring conversations move through well-defined states. Tool calls during streaming support both automatic execution (via MCP) and manual approval through the UI.

## Who Is Liteskill For?

- **Teams** that want a private, self-hosted alternative to ChatGPT or Claude with full data ownership
- **Organizations** that need audit trails and compliance -- every interaction is recorded as an immutable event
- **Developers** building AI workflows who need MCP tool integration, multi-agent pipelines, and RAG in a single platform
- **Enterprises** that require SSO, group-based access control, and encrypted credential storage

## License

Liteskill is released under the **Apache License 2.0**. See the [LICENSE](https://github.com/liteskill/liteskill-oss/blob/main/LICENSE) file for the full text.
