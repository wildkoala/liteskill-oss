# LLM Context

Modules: `Liteskill.LLM`, `Liteskill.LlmProviders`, `Liteskill.LlmModels`, `Liteskill.LLM.StreamHandler`

## Liteskill.LLM

Public API for LLM interactions. Uses ReqLLM for transport. Models are configured in the database via admin UI -- there are no hardcoded model IDs or env-var fallbacks for model selection.

### `complete(messages, opts \\ [])`

Sends a non-streaming completion request. Used for tasks like conversation title generation.

```elixir
complete(list(), keyword())
:: {:ok, map()} | {:error, term()}
```

Options:
- `:llm_model` -- a `%LlmModel{}` struct with full provider config (preferred)
- `:model_id` -- model ID string (requires `:provider_options` too)
- `:max_tokens` -- maximum tokens to generate
- `:temperature` -- sampling temperature
- `:system` -- system prompt
- `:generate_fn` -- override the generation function (for testing)
- `:user_id` -- user ID for usage recording
- `:conversation_id` -- conversation ID for usage recording

### `available_models(user_id)`

Lists active inference models available to the given user. Delegates to `LlmModels.list_active_models/2` with `model_type: "inference"`.

```elixir
available_models(binary_id) :: [LlmModel.t()]
```

## Liteskill.LlmProviders

Context for managing LLM provider configurations. Each provider represents a connection endpoint with credentials.

### LlmProvider Schema

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Required |
| `provider_type` | `:string` | e.g. `"amazon_bedrock"`, `"azure"`, `"openai"` |
| `api_key` | `:string` | Encrypted at rest |
| `provider_config` | `:map` | Encrypted at rest (region, base_url, etc.) |
| `instance_wide` | `:boolean` | If true, available to all users |
| `status` | `:string` | `"active"` or `"inactive"` |
| `user_id` | `:binary_id` | Owner |

### `create_provider(attrs)`

Creates a provider and auto-creates an owner ACL.

```elixir
create_provider(map()) :: {:ok, LlmProvider.t()} | {:error, Ecto.Changeset.t()}
```

### `update_provider(id, user_id, attrs)`

Updates a provider. Owner only.

```elixir
update_provider(binary_id, binary_id, map())
:: {:ok, LlmProvider.t()} | {:error, :not_found | :forbidden}
```

### `delete_provider(id, user_id)`

Deletes a provider. Owner only.

```elixir
delete_provider(binary_id, binary_id)
:: {:ok, LlmProvider.t()} | {:error, :not_found | :forbidden}
```

### `list_providers(user_id)`

Lists providers the user can access: owned, instance-wide, or ACL-shared.

```elixir
list_providers(binary_id) :: [LlmProvider.t()]
```

### `get_provider(id, user_id)`

Gets a provider if accessible to the user (owner, instance_wide, or ACL).

```elixir
get_provider(binary_id, binary_id)
:: {:ok, LlmProvider.t()} | {:error, :not_found}
```

### `get_provider!(id)`

Gets a provider by ID without authorization. Raises if not found.

```elixir
get_provider!(binary_id) :: LlmProvider.t()
```

### `ensure_env_providers()`

Boot-time task. Creates or updates an instance-wide Bedrock provider from env var config (`bedrock_bearer_token` in app config). Idempotent.

```elixir
ensure_env_providers() :: :ok
```

### `get_bedrock_credentials()`

Returns Bedrock credentials from the first active instance-wide Bedrock provider. Returns `nil` if none found.

```elixir
get_bedrock_credentials()
:: %{api_key: String.t(), region: String.t()} | nil
```

## Liteskill.LlmModels

Context for managing LLM model configurations. Each model references an LLM provider for endpoint credentials.

### LlmModel Schema

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Display name |
| `model_id` | `:string` | Provider model identifier (e.g. `"anthropic.claude-3-5-sonnet-20241022-v2:0"`) |
| `model_type` | `:string` | `"inference"`, `"embedding"`, or `"rerank"` |
| `model_config` | `:map` | Encrypted at rest |
| `instance_wide` | `:boolean` | If true, available to all users |
| `status` | `:string` | `"active"` or `"inactive"` |
| `input_cost_per_million` | `:decimal` | Cost per million input tokens |
| `output_cost_per_million` | `:decimal` | Cost per million output tokens |
| `provider_id` | `:binary_id` | FK to LlmProvider |
| `user_id` | `:binary_id` | Owner |

### `create_model(attrs)`

Creates a model and auto-creates an owner ACL.

```elixir
create_model(map()) :: {:ok, LlmModel.t()} | {:error, Ecto.Changeset.t()}
```

### `update_model(id, user_id, attrs)`

Updates a model. Owner only.

```elixir
update_model(binary_id, binary_id, map())
:: {:ok, LlmModel.t()} | {:error, :not_found | :forbidden}
```

### `delete_model(id, user_id)`

Deletes a model. Owner only.

```elixir
delete_model(binary_id, binary_id)
:: {:ok, LlmModel.t()} | {:error, :not_found | :forbidden}
```

### `list_models(user_id)`

Lists all models accessible to the user (owned, instance-wide, or ACL-shared). Preloads provider.

```elixir
list_models(binary_id) :: [LlmModel.t()]
```

### `list_active_models(user_id, opts \\ [])`

Lists active models from active providers accessible to the user.

```elixir
list_active_models(binary_id, keyword()) :: [LlmModel.t()]
```

Options:
- `:model_type` -- filter by model type (e.g. `"inference"`, `"embedding"`)

### `get_model(id, user_id)`

Gets a model if accessible to the user.

```elixir
get_model(binary_id, binary_id)
:: {:ok, LlmModel.t()} | {:error, :not_found}
```

### `build_provider_options(llm_model)`

Builds ReqLLM-compatible provider options from a model and its preloaded provider. Returns `{model_spec, req_opts}`.

```elixir
build_provider_options(LlmModel.t())
:: {%{id: String.t(), provider: atom()}, keyword()}
```

## Liteskill.LLM.StreamHandler

Orchestrates streaming LLM calls with event store integration. Handles the full lifecycle: start stream, record chunks, handle tool calls, complete/fail stream, and record usage.

### `handle_stream(stream_id, messages, opts \\ [])`

Handles a full streaming LLM call for a conversation. Meant to be called asynchronously after a user message is added.

```elixir
handle_stream(String.t(), list(), keyword())
:: :ok | {:error, term()}
```

Options:
- `:llm_model` -- `%LlmModel{}` struct (preferred)
- `:model_id` -- model ID string fallback
- `:system` -- system prompt
- `:tools` -- list of tool specs (toolConfig format)
- `:tool_servers` -- map of `"tool_name" => server` for MCP execution
- `:auto_confirm` -- boolean, auto-execute tool calls (default: `false`)
- `:backoff_ms` -- base backoff for retries (default: 1000)
- `:tool_approval_timeout_ms` -- timeout for manual tool approval (default: 300,000ms / 5 minutes)
- `:max_tool_rounds` -- max consecutive tool-calling rounds (default: 10)
- `:stream_fn` -- override the LLM streaming function (for testing)
- `:rag_sources` -- RAG source metadata to attach to the assistant message
- `:user_id` -- user ID for usage recording
- `:conversation_id` -- conversation ID for usage recording
- `:temperature` -- sampling temperature
- `:max_tokens` -- max tokens to generate

### Streaming Flow

1. Execute `start_assistant_stream` command on the aggregate (transitions `:active` -> `:streaming`)
2. Stream from LLM via ReqLLM
3. On each text chunk: execute `receive_chunk` command, project events asynchronously
4. On tool calls: validate against allowed tools, execute `start_tool_call` for each, then either auto-execute via MCP or await manual approval via PubSub
5. On completion: execute `complete_stream` command (transitions `:streaming` -> `:active`), record usage
6. On failure: execute `fail_stream` command (transitions `:streaming` -> `:active`)
7. On 429/503 errors: retry with exponential backoff (max 3 retries)
8. After tool execution: build next messages with assistant content + tool results, recurse into `handle_stream` (incrementing tool round)

### Helper Functions

#### `validate_tool_calls(tool_calls, tools)`

Filters tool calls to only include those whose names appear in the allowed tools list. Returns empty list if no tools are configured.

#### `build_assistant_content(full_content, tool_calls)`

Builds the assistant content blocks (text + toolUse) for the next conversation round after tool calls.

#### `format_tool_output(result)`

Formats tool execution output into a string for inclusion in conversation messages.
