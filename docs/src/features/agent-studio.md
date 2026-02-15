# Agent Studio

Agent Studio lets you define reusable AI agents, assemble them into teams, and execute multi-agent pipelines that produce structured deliverables. It provides a framework for orchestrating specialized AI workflows where different agents contribute distinct perspectives and expertise.

## Overview

The Agent Studio system consists of three core concepts:

- **Agents** -- Individual AI "character sheets" with a name, backstory, strategy, model, and tool assignments
- **Teams** -- Ordered collections of agents with assigned roles and execution positions
- **Runs** -- Runtime executions that process a prompt through a team's pipeline and produce deliverables

All three entity types use the same ACL system for sharing, so you can collaborate on agent definitions, team configurations, and run results with other users.

## Agents

An agent definition is the "character sheet" for an AI agent. It specifies everything the agent needs to operate: its personality, reasoning approach, knowledge base, and available tools.

### Agent Fields

| Field | Description |
|---|---|
| `name` | Unique name for the agent (unique per user) |
| `description` | Human-readable description |
| `backstory` | Background narrative that shapes the agent's perspective |
| `opinions` | Key-value pairs representing the agent's stances on topics |
| `system_prompt` | Optional system prompt sent to the LLM |
| `strategy` | Reasoning strategy (see below) |
| `config` | Additional configuration as JSON |
| `status` | `active` or `inactive` |
| `llm_model_id` | The LLM model the agent uses for inference |

### Strategies

The strategy field determines how the agent approaches problem-solving:

| Strategy | Description |
|---|---|
| `react` | ReAct (Reasoning + Acting) -- interleaves reasoning with tool use (default) |
| `chain_of_thought` | Step-by-step reasoning before producing output |
| `tree_of_thoughts` | Explores multiple reasoning paths and selects the best |
| `direct` | Generates output directly without explicit reasoning structure |

### Backstory and Opinions

The backstory provides narrative context that shapes how the agent interprets and responds to prompts. For example, a "Senior Security Analyst" agent might have a backstory describing years of experience in cybersecurity, which influences its analysis perspective.

Opinions are key-value pairs that encode specific stances:

```json
{
  "code_quality": "Always prioritize readability over cleverness",
  "testing": "Integration tests provide more value than unit tests for APIs",
  "documentation": "Code should be self-documenting with minimal comments"
}
```

These are injected into the agent's context during execution, guiding its outputs toward consistent perspectives.

### Tool Assignments

Agents can be connected to MCP servers (and built-in tools) through the `agent_tools` join table. Each assignment links an agent to an MCP server, optionally scoped to a specific tool name:

- **Server-level assignment** -- The agent can use all tools from the server
- **Tool-level assignment** -- The agent can only use the specific named tool

During execution, the `ToolResolver` resolves all assigned tools by:

1. Listing available tools from each assigned MCP server
2. Filtering to only the assigned tool names (if specified)
3. Building the tool specifications and server mapping for the LLM call

## Teams

Teams are ordered collections of agents that execute together. Each team member has a role and position that determines the execution order.

### Team Fields

| Field | Description |
|---|---|
| `name` | Team name (unique per user) |
| `description` | Human-readable description |
| `shared_context` | Text context shared across all team members |
| `default_topology` | Execution topology: `pipeline`, `parallel`, `debate`, `hierarchical`, or `round_robin` |
| `aggregation_strategy` | How to combine agent outputs: `last`, `merge`, or `vote` |
| `config` | Additional configuration |
| `status` | `active` or `inactive` |

### Team Members

Each team member links an agent definition to a team with:

| Field | Description |
|---|---|
| `role` | The agent's role in the team (e.g., `lead`, `analyst`, `reviewer`, `editor`, `worker`) |
| `description` | Description of this member's responsibilities |
| `position` | Execution order (0-indexed, ascending) |

Members are automatically sorted by position. When adding a member without specifying a position, the system assigns the next available position.

## Runs

A run is a runtime execution that processes a prompt through a team's pipeline and produces deliverables.

### Run Fields

| Field | Description |
|---|---|
| `name` | Run name |
| `description` | Optional description |
| `prompt` | The input prompt to process |
| `topology` | Execution topology (defaults to `pipeline`) |
| `status` | `pending`, `running`, `completed`, `failed`, or `cancelled` |
| `context` | Additional context as JSON |
| `deliverables` | Output map (e.g., `{"report_id": "..."}`) |
| `error` | Error message if failed |
| `timeout_ms` | Maximum execution time (default 1,800,000 ms / 30 minutes) |
| `max_iterations` | Maximum iteration count (default 50) |
| `team_definition_id` | The team that executes this run |

### Run Lifecycle

```
pending --> running --> completed
                   \--> failed
                   \--> cancelled
```

1. **pending** -- Created but not yet started
2. **running** -- Actively executing; `started_at` is set
3. **completed** -- Successfully finished; deliverables contain the report ID
4. **failed** -- Execution error or timeout; `error` field has details
5. **cancelled** -- Manually cancelled by the user while running

### Pipeline Execution

The `Runner` module orchestrates run execution through the following process:

1. **Resolve agents** -- Load all team members sorted by position, resolve their agent definitions and LLM models

2. **Create report** -- Use the built-in Reports tool to create a new report as the run's deliverable. The report title combines the run name with agent names.

3. **Write overview** -- Create an overview section documenting the prompt, topology, pipeline stages, and execution plan

4. **Execute agent stages** -- For each team member, in position order:
   - Log the stage start with agent name, role, strategy, and model
   - Create a `RunTask` record to track the stage
   - Build a Jido agent with the agent's full configuration (system prompt, backstory, opinions, tools)
   - Call the LLM via `LlmGenerate` with the agent's context
   - Write three report sections per agent:
     - **Configuration** -- Agent settings, model, system prompt, backstory
     - **Analysis** -- The agent's analytical output
     - **Output** -- The agent's primary deliverable
   - Pass context forward: each subsequent agent sees all prior agents' outputs

5. **Write closing sections** -- Append a Pipeline Summary and Conclusion to the report

6. **Finalize** -- Mark the run as completed with the report ID in deliverables, or failed with the error message

### Context Accumulation

As the pipeline progresses, context accumulates. Each agent receives:

- The original prompt
- All prior agents' outputs (formatted as `--- AgentName (role) ---\noutput text`)

Prior context is truncated to 8,000 characters per agent to stay within token limits. This ensures later agents can build on earlier analysis while maintaining reasonable prompt sizes.

### Run Tasks and Logs

Each agent stage creates a `RunTask` record tracking:

- Task name, description, and position
- Status (`running`, `completed`, `failed`)
- Duration in milliseconds
- Output summary or error message
- Start and completion timestamps

The runner also writes detailed `RunLog` entries at each step (initialization, agent resolution, tool resolution, LLM calls, completions, and errors) with structured metadata for debugging.

## Jido Framework Integration

Agent execution uses the Jido framework through `JidoAgent` and the `LlmGenerate` action:

1. `JidoAgent.new/1` creates a Jido-compatible agent struct from the agent definition's state
2. `LlmGenerate.run/2` executes the LLM call with the agent's full context, including system prompt, backstory, opinions, role, prior context, tools, and tool servers
3. The action returns structured output with `analysis` and `output` sections

## ACL Sharing

All Agent Studio entities support ACL-based sharing:

- **Agents** -- Share agent definitions so other users can include them in their teams
- **Teams** -- Share team configurations for collaborative pipeline design
- **Runs** -- Share run results so others can view deliverables and logs
