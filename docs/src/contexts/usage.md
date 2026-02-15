# Usage Tracking

Module: `Liteskill.Usage`

Context for recording and querying LLM token usage. Usage records are stored in a dedicated projection table (`llm_usage_records`), independent of the event store, for efficient aggregation queries by user, conversation, model, and time period.

## UsageRecord Schema

`Liteskill.Usage.UsageRecord`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `model_id` | `:string` | Provider model identifier string |
| `input_tokens` | `:integer` | Default: 0 |
| `output_tokens` | `:integer` | Default: 0 |
| `total_tokens` | `:integer` | Default: 0 |
| `reasoning_tokens` | `:integer` | Default: 0 |
| `cached_tokens` | `:integer` | Default: 0 |
| `cache_creation_tokens` | `:integer` | Default: 0 |
| `input_cost` | `:decimal` | Cost for input tokens |
| `output_cost` | `:decimal` | Cost for output tokens |
| `reasoning_cost` | `:decimal` | Cost for reasoning tokens |
| `total_cost` | `:decimal` | Total cost |
| `latency_ms` | `:integer` | Response latency |
| `call_type` | `:string` | `"stream"` or `"complete"` (required) |
| `tool_round` | `:integer` | Tool calling round number (default: 0) |
| `message_id` | `:binary_id` | Optional message association |
| `user_id` | `:binary_id` | Required, FK to User |
| `conversation_id` | `:binary_id` | Optional, FK to Conversation |
| `llm_model_id` | `:binary_id` | Optional, FK to LlmModel |
| `run_id` | `:binary_id` | Optional, FK to Run |

Note: `updated_at` is not tracked (insert-only table).

## Recording Usage

### `record_usage(attrs)`

Records a single LLM API call's usage. Low-level insert function.

```elixir
record_usage(map())
:: {:ok, UsageRecord.t()} | {:error, Ecto.Changeset.t()}
```

Required attrs: `:user_id`, `:model_id`, `:call_type`

### `record_from_response(usage, opts)`

Builds and records a usage record from an API response usage map. Resolves costs via `CostCalculator`, assembles all fields, and inserts. No-ops (returns `:ok`) when `user_id` is nil.

```elixir
record_from_response(map() | nil, keyword()) :: :ok
```

Options:
- `:user_id` -- required for recording
- `:llm_model` -- `%LlmModel{}` struct for model_id and cost rate lookup
- `:model_id` -- fallback model ID string (used when no `:llm_model`)
- `:conversation_id` -- optional conversation association
- `:message_id` -- optional message association
- `:run_id` -- optional run association
- `:call_type` -- `"stream"` or `"complete"` (required)
- `:latency_ms` -- response latency in milliseconds
- `:tool_round` -- tool calling round number (default: 0)

## CostCalculator

Module: `Liteskill.Usage.CostCalculator`

Shared cost-resolution logic. Prefers API-reported costs from the usage map, falling back to model rate-based calculation using `input_cost_per_million` and `output_cost_per_million` fields on `LlmModel`.

### `resolve_costs(usage, llm_model, input_tokens, output_tokens)`

Returns `{input_cost, output_cost, total_cost}` where each is a `Decimal` or `nil`.

```elixir
resolve_costs(map(), LlmModel.t() | nil, integer(), integer())
:: {Decimal.t() | nil, Decimal.t() | nil, Decimal.t() | nil}
```

### `to_decimal(value)`

Converts a value to `Decimal`, handling `nil`, floats, integers, and passthrough for existing `Decimal` values.

## Query Functions

All aggregation queries return maps with summed token counts and costs.

### `usage_by_conversation(conversation_id)`

Returns aggregated usage for a conversation.

```elixir
usage_by_conversation(binary_id) :: map()
```

Returns: `%{input_tokens, output_tokens, total_tokens, reasoning_tokens, cached_tokens, input_cost, output_cost, total_cost, call_count}`

### `usage_by_user(user_id, opts \\ [])`

Returns aggregated usage for a user.

```elixir
usage_by_user(binary_id, keyword()) :: map()
```

Options:
- `:from` -- start datetime (inclusive)
- `:to` -- end datetime (exclusive)

### `usage_by_user_and_model(user_id, opts \\ [])`

Returns usage for a user grouped by model. Ordered by total tokens descending.

```elixir
usage_by_user_and_model(binary_id, keyword()) :: [map()]
```

### `usage_by_group(group_id, opts \\ [])`

Returns aggregated usage for all members of a group.

```elixir
usage_by_group(binary_id, keyword()) :: map()
```

### `usage_by_groups(group_ids, opts \\ [])`

Returns aggregated usage for multiple groups in a single query. Returns a map of `group_id => usage_map`. Groups with no usage are included with zeroed values.

```elixir
usage_by_groups([binary_id], keyword()) :: %{binary_id => map()}
```

### `usage_by_run(run_id)`

Returns aggregated usage for a run.

```elixir
usage_by_run(binary_id) :: map()
```

### `usage_by_run_and_model(run_id)`

Returns usage for a run grouped by model.

```elixir
usage_by_run_and_model(binary_id) :: [map()]
```

### `usage_summary(opts \\ [])`

Flexible usage query builder with optional filtering and grouping.

```elixir
usage_summary(keyword()) :: map() | [map()]
```

Options:
- `:user_id` -- filter by user
- `:conversation_id` -- filter by conversation
- `:model_id` -- filter by model ID string
- `:from` -- start datetime (inclusive)
- `:to` -- end datetime (exclusive)
- `:group_by` -- `:model_id`, `:user_id`, or `:conversation_id` (returns a list when set, a single map when not)

### `instance_totals(opts \\ [])`

Returns instance-wide usage totals.

```elixir
instance_totals(keyword()) :: map()
```

### `daily_totals(opts \\ [])`

Returns daily usage totals for the given time range, grouped by date. Supports the same filter options as `usage_summary/1`.

```elixir
daily_totals(keyword()) :: [map()]
```

Each entry: `%{date, total_tokens, input_cost, output_cost, total_cost, call_count}`

## Integration with StreamHandler

The `StreamHandler` records usage on stream completion by calling `Usage.record_from_response/2` with the API-reported usage map and stream metadata (user_id, conversation_id, message_id, model, latency, call_type, tool_round).

The `LLM.complete/2` function similarly records usage for non-streaming calls.
