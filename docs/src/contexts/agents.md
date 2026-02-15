# Agents, Teams & Runs

Modules: `Liteskill.Agents`, `Liteskill.Teams`, `Liteskill.Runs`

## Agents

Module: `Liteskill.Agents`

Context for managing agent definitions. Agent definitions are the "character sheets" for AI agents -- name, backstory, opinions, strategy, model, and tool assignments. All operations are ACL-controlled.

### AgentDefinition Schema

`Liteskill.Agents.AgentDefinition`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Required |
| `description` | `:string` | |
| `strategy` | `:string` | `"react"`, `"chain_of_thought"`, `"tree_of_thoughts"`, or `"direct"` |
| `backstory` | `:string` | Agent persona/background |
| `opinions` | `:map` | Key-value pairs representing agent opinions |
| `system_prompt` | `:string` | System prompt for the LLM |
| `status` | `:string` | Agent status |
| `llm_model_id` | `:binary_id` | FK to LlmModel |
| `user_id` | `:binary_id` | Owner |

### AgentTool Schema

`Liteskill.Agents.AgentTool`

Join table binding agents to MCP server tools.

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `tool_name` | `:string` | Specific tool name (nullable = all tools from server) |
| `agent_definition_id` | `:binary_id` | FK to AgentDefinition |
| `mcp_server_id` | `:binary_id` | FK to McpServer |

### CRUD

#### `create_agent(attrs)`

Creates an agent definition with owner ACL. Preloads `:llm_model` and `agent_tools: :mcp_server`.

```elixir
create_agent(map())
:: {:ok, AgentDefinition.t()} | {:error, Ecto.Changeset.t()}
```

Required attrs: `:name`, `:user_id`

#### `update_agent(id, user_id, attrs)`

Updates an agent. Owner only.

```elixir
update_agent(binary_id, binary_id, map())
:: {:ok, AgentDefinition.t()} | {:error, :not_found | :forbidden}
```

#### `delete_agent(id, user_id)`

Deletes an agent. Owner only.

```elixir
delete_agent(binary_id, binary_id)
:: {:ok, AgentDefinition.t()} | {:error, :not_found | :forbidden}
```

#### `list_agents(user_id)`

Lists agents accessible to the user (owned or ACL-shared).

```elixir
list_agents(binary_id) :: [AgentDefinition.t()]
```

#### `get_agent(id, user_id)`

Gets an agent if accessible. Preloads `llm_model: :provider` and `agent_tools: :mcp_server`.

```elixir
get_agent(binary_id, binary_id)
:: {:ok, AgentDefinition.t()} | {:error, :not_found}
```

#### `get_agent!(id)`

Gets an agent without authorization. Raises if not found.

### Tool Management

#### `add_tool(agent_definition_id, mcp_server_id, tool_name \\ nil, user_id)`

Binds a tool to an agent. If `tool_name` is nil, all tools from the server are bound. Owner only.

```elixir
add_tool(binary_id, binary_id, String.t() | nil, binary_id)
:: {:ok, AgentTool.t()} | {:error, :not_found | :forbidden}
```

#### `remove_tool(agent_definition_id, mcp_server_id, tool_name \\ nil, user_id)`

Removes a tool binding. Owner only.

```elixir
remove_tool(binary_id, binary_id, String.t() | nil, binary_id)
:: {:ok, AgentTool.t()} | {:error, :not_found | :forbidden}
```

#### `list_tools(agent_definition_id)`

Lists all tool bindings for an agent, preloading MCP server.

```elixir
list_tools(binary_id) :: [AgentTool.t()]
```

### ToolResolver

`Liteskill.Agents.ToolResolver`

Resolves tools for agent execution. Takes an agent definition, queries all bound MCP servers for their tool lists, and returns `{tools, tool_servers}` where `tools` is the list of tool specs and `tool_servers` is a map of `tool_name => server`.

### JidoAgent

`Liteskill.Agents.JidoAgent`

Integration with the Jido agent framework. Wraps agent state for use with Jido actions.

---

## Teams

Module: `Liteskill.Teams`

Context for managing team definitions. Teams are named collections of agents with execution topology.

### TeamDefinition Schema

`Liteskill.Teams.TeamDefinition`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Required |
| `description` | `:string` | |
| `user_id` | `:binary_id` | Owner |

### TeamMember Schema

`Liteskill.Teams.TeamMember`

Join table linking teams to agents with execution metadata.

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `role` | `:string` | `"lead"`, `"analyst"`, `"reviewer"`, `"editor"`, or `"worker"` (default: `"worker"`) |
| `description` | `:string` | Member-specific task description |
| `position` | `:integer` | Execution order (default: 0) |
| `team_definition_id` | `:binary_id` | FK to TeamDefinition |
| `agent_definition_id` | `:binary_id` | FK to AgentDefinition |

Unique constraint on `(team_definition_id, agent_definition_id)`.

### CRUD

#### `create_team(attrs)`

Creates a team definition with owner ACL. Preloads `team_members: :agent_definition`.

```elixir
create_team(map())
:: {:ok, TeamDefinition.t()} | {:error, Ecto.Changeset.t()}
```

Required attrs: `:name`, `:user_id`

#### `update_team(id, user_id, attrs)`

Updates a team. Owner only.

```elixir
update_team(binary_id, binary_id, map())
:: {:ok, TeamDefinition.t()} | {:error, :not_found | :forbidden}
```

#### `delete_team(id, user_id)`

Deletes a team. Owner only.

```elixir
delete_team(binary_id, binary_id)
:: {:ok, TeamDefinition.t()} | {:error, :not_found | :forbidden}
```

#### `list_teams(user_id)`

Lists teams accessible to the user.

```elixir
list_teams(binary_id) :: [TeamDefinition.t()]
```

#### `get_team(id, user_id)`

Gets a team if accessible.

```elixir
get_team(binary_id, binary_id)
:: {:ok, TeamDefinition.t()} | {:error, :not_found}
```

### Member Management

#### `add_member(team_definition_id, agent_definition_id, user_id, attrs \\ %{})`

Adds an agent to a team. Auto-assigns the next position. Team owner only.

```elixir
add_member(binary_id, binary_id, binary_id, map())
:: {:ok, TeamMember.t()} | {:error, :not_found | :forbidden}
```

#### `remove_member(team_definition_id, agent_definition_id, user_id)`

Removes an agent from a team. Team owner only.

```elixir
remove_member(binary_id, binary_id, binary_id)
:: {:ok, TeamMember.t()} | {:error, :not_found | :forbidden}
```

#### `update_member(member_id, user_id, attrs)`

Updates a team member's role, description, or position. Team owner only.

```elixir
update_member(binary_id, binary_id, map())
:: {:ok, TeamMember.t()} | {:error, :not_found | :forbidden}
```

---

## Runs

Module: `Liteskill.Runs`

Context for managing runs -- runtime task executions.

### Run Schema

`Liteskill.Runs.Run`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Required |
| `description` | `:string` | |
| `prompt` | `:string` | Required -- the task prompt |
| `topology` | `:string` | `"pipeline"`, `"parallel"`, `"debate"`, `"hierarchical"`, or `"round_robin"` (default: `"pipeline"`) |
| `status` | `:string` | `"pending"`, `"running"`, `"completed"`, `"failed"`, or `"cancelled"` (default: `"pending"`) |
| `context` | `:map` | Execution context (default: `%{}`) |
| `deliverables` | `:map` | Output references, e.g. `%{"report_id" => id}` (default: `%{}`) |
| `error` | `:string` | Error message on failure |
| `timeout_ms` | `:integer` | Execution timeout (default: 1,800,000ms / 30 minutes) |
| `max_iterations` | `:integer` | Default: 50 |
| `started_at` | `:utc_datetime` | |
| `completed_at` | `:utc_datetime` | |
| `team_definition_id` | `:binary_id` | FK to TeamDefinition |
| `user_id` | `:binary_id` | Owner |

### RunTask Schema

`Liteskill.Runs.RunTask`

Individual tasks within a run, ordered by position.

| Field | Type | Notes |
|---|---|---|
| `name` | `:string` | |
| `description` | `:string` | |
| `status` | `:string` | Task status |
| `position` | `:integer` | Execution order |
| `output_summary` | `:string` | Brief summary of output |
| `error` | `:string` | Error message on failure |
| `duration_ms` | `:integer` | Task duration |
| `started_at`, `completed_at` | `:utc_datetime` | |
| `agent_definition_id` | `:binary_id` | FK to AgentDefinition |
| `run_id` | `:binary_id` | FK to Run |

### RunLog Schema

`Liteskill.Runs.RunLog`

Execution logs for a run.

| Field | Type | Notes |
|---|---|---|
| `level` | `:string` | e.g. `"info"`, `"error"` |
| `step` | `:string` | e.g. `"init"`, `"agent_start"`, `"llm_call"` |
| `message` | `:string` | Log message |
| `metadata` | `:map` | Additional structured data |
| `run_id` | `:binary_id` | FK to Run |

### CRUD

#### `create_run(attrs)`

Creates a run with owner ACL. Preloads `:team_definition`, `:run_tasks`, `:run_logs`.

```elixir
create_run(map())
:: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
```

Required attrs: `:name`, `:prompt`, `:user_id`

#### `update_run(id, user_id, attrs)`, `delete_run(id, user_id)`

Owner only.

#### `cancel_run(id, user_id)`

Cancels a running run. Only works when status is `"running"`.

```elixir
cancel_run(binary_id, binary_id)
:: {:ok, Run.t()} | {:error, :not_found | :not_running | :forbidden}
```

#### `list_runs(user_id)`

Lists runs accessible to the user, ordered by most recent.

```elixir
list_runs(binary_id) :: [Run.t()]
```

#### `get_run(id, user_id)`

Gets a run if accessible.

```elixir
get_run(binary_id, binary_id)
:: {:ok, Run.t()} | {:error, :not_found}
```

### Task Management

#### `add_task(run_id, attrs)`

Adds a task to a run.

```elixir
add_task(binary_id, map())
:: {:ok, RunTask.t()} | {:error, Ecto.Changeset.t()}
```

#### `update_task(task_id, attrs)`

Updates a task.

```elixir
update_task(binary_id, map())
:: {:ok, RunTask.t()} | {:error, :not_found}
```

### Log Management

#### `add_log(run_id, level, step, message, metadata \\ %{})`

Adds a log entry to a run.

```elixir
add_log(binary_id, String.t(), String.t(), String.t(), map())
:: {:ok, RunLog.t()} | {:error, Ecto.Changeset.t()}
```

#### `get_log(log_id, user_id)`

Gets a log entry if the user has access to the parent run.

```elixir
get_log(binary_id, binary_id)
:: {:ok, RunLog.t()} | {:error, :not_found}
```

### Runner

`Liteskill.Runs.Runner`

Executes a run by processing its prompt through the configured team's agents.

#### `Runner.run(run_id, user_id)`

Entry point for run execution. Called from `Task.Supervisor`.

Execution flow:

1. Mark run as `"running"`
2. Resolve agents from the team (sorted by position)
3. Create a report with title `"<run name> -- <agent names>"`
4. Write an "Overview" section with prompt, topology, and pipeline stages
5. Execute each agent sequentially in a pipeline:
   - Resolve tools via `ToolResolver`
   - Build agent state with system prompt, backstory, opinions, prior context
   - Call LLM via `JidoAgent` / `LlmGenerate` action
   - Write Configuration, Analysis, and Output sections to the report
   - Pass accumulated context to the next agent
6. Write "Pipeline Summary" and "Conclusion" sections
7. Mark run as `"completed"` with `deliverables: %{"report_id" => id}`
8. On failure or timeout: mark run as `"failed"` with error details

Each agent stage creates a `RunTask` and logs progress via `RunLog`.
