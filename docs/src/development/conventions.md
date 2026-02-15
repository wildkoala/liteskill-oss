# Code Conventions

This page documents the coding standards and conventions used throughout the Liteskill codebase.

## Database Conventions

### Primary Keys

All tables use **binary UUIDs** as primary keys:

```elixir
@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
```

### Timestamps

All schemas use `:utc_datetime` for timestamp fields:

```elixir
timestamps(type: :utc_datetime)
```

This is configured globally in `config.exs`:

```elixir
config :liteskill,
  generators: [timestamp_type: :utc_datetime]
```

### Text Fields

All text columns use the `:string` Ecto type, even for columns that are `text` in PostgreSQL:

```elixir
field :content, :string
field :system_prompt, :string
```

This simplifies the schema layer -- Ecto's `:string` type works with both `varchar` and `text` columns.

### Foreign Keys

Foreign keys (e.g., `user_id`, `conversation_id`) are set programmatically in context functions, never in `cast`:

```elixir
# Good -- set in context
def create_conversation(attrs) do
  %Conversation{}
  |> Conversation.changeset(attrs)
  |> Ecto.Changeset.put_change(:user_id, attrs.user_id)
  |> Repo.insert()
end

# Bad -- never cast foreign keys from user input
def changeset(conversation, attrs) do
  conversation
  |> cast(attrs, [:title, :user_id])  # Don't do this
end
```

This prevents privilege escalation via user-supplied foreign key values.

## Event Sourcing Conventions

### Event Serialization

Events are stored with **string keys** (not atom keys) using `stringify_keys`:

```elixir
%{"type" => "MessageSent", "conversation_id" => "...", "content" => "..."}
```

Deserialization converts stored events back to structs via `Events.deserialize/1`.

### Stream IDs

Event streams use the format `"conversation-<uuid>"`:

```elixir
stream_id = "conversation-#{conversation_id}"
```

### Aggregate State Machine

The `ConversationAggregate` follows a state machine: `:created` -> `:active` <-> `:streaming` -> `:archived`. Tool calls are handled in both `:streaming` and `:active` states.

## HTTP Conventions

### Req Library Only

All HTTP calls must use the [Req](https://hex.pm/packages/req) library. Never use HTTPoison, Tesla, or `:httpc`:

```elixir
# Good
Req.post!(url, json: body, plug: test_plug)

# Bad
HTTPoison.post(url, body)
Tesla.post(url, body)
:httpc.request(:post, {url, headers, content_type, body}, [], [])
```

This ensures consistent HTTP behavior, testing (via `Req.Test`), and middleware support across the codebase.

## Phoenix Conventions

### Contexts as Bounded Contexts

Phoenix contexts serve as bounded contexts with clear boundaries:

| Context | Responsibility |
|---------|---------------|
| `Liteskill.Chat` | Conversations, messages, forking, ACLs |
| `Liteskill.Accounts` | Users, authentication, profiles |
| `Liteskill.Groups` | Groups, memberships |
| `Liteskill.McpServers` | MCP server CRUD, JSON-RPC client |
| `Liteskill.LlmProviders` | LLM provider management |
| `Liteskill.LlmModels` | LLM model management |
| `Liteskill.DataSources` | RAG data sources |
| `Liteskill.Agents` | Agent definitions |
| `Liteskill.Teams` | Agent team definitions |
| `Liteskill.Runs` | Agent run execution |
| `Liteskill.Schedules` | Scheduled runs |

All `Chat` context functions require a `user_id` parameter for authorization.

### Phoenix 1.8.3

The project uses Phoenix 1.8.3 conventions:
- LiveView for interactive UI
- Function components with HEEx templates
- Verified routes (`~p` sigil)
- Bandit as the HTTP server adapter

## CSS Conventions

### Tailwind CSS v4

Liteskill uses Tailwind CSS v4, which has a different configuration model than v3:

- **No `tailwind.config.js`** -- Configuration is done via CSS `@import` and `@theme` directives in `assets/css/app.css`
- Use `@import "tailwindcss"` syntax
- daisyUI provides component classes (buttons, cards, modals, etc.)

### No `@apply`

Avoid using Tailwind's `@apply` directive in CSS files. Use utility classes directly in templates:

```heex
<!-- Good -->
<div class="flex items-center gap-2 p-4 bg-base-100 rounded-lg">

<!-- Avoid -->
<div class="custom-card">
```

## Naming Conventions

### Modules

- Context modules: `Liteskill.<ContextName>` (e.g., `Liteskill.Chat`)
- Schema modules: `Liteskill.<Context>.<Schema>` (e.g., `Liteskill.Chat.Conversation`)
- Web modules: `LiteskillWeb.<Name>` (e.g., `LiteskillWeb.ChatLive`)
- Component modules: `LiteskillWeb.<Name>Components` (e.g., `LiteskillWeb.ChatComponents`)

### Files

- Elixir files use `snake_case.ex`
- Test files mirror `lib/` structure under `test/` with `_test.exs` suffix
- Migration files use the standard `YYYYMMDDHHMMSS_description.exs` format
