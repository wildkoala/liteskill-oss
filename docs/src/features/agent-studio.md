# Agent Studio

The Agent Studio lets users define reusable AI agents with specific configurations, tool access, and data source access.

## Agent Definitions

Each agent definition includes:

- **Name** and **backstory** — Identity and persona
- **Strategy** and **opinions** — Behavioral guidance
- **LLM model** — The model the agent uses for inference
- **Tool access** — ACL-controlled access to specific MCP servers
- **Data source access** — ACL-controlled access to specific data sources for RAG

## Tool Access

Agents are granted access to MCP servers via ACLs on the `mcp_server` entity type. During execution, the `ToolResolver` resolves which tools the agent can use based on its ACLs.

## Data Source Access

Similarly, agents can be granted access to data sources. During runs, the agent's RAG context is scoped to only the data sources it has access to.

## Teams

Agents can be composed into teams with different topologies:

- **Sequential** — Agents execute in order, passing results forward
- **Parallel** — Agents execute concurrently
- **Supervisor** — A supervisor agent coordinates other agents

## Execution

Agents execute through the `Runs` system. A run tracks the full lifecycle of an agent or team execution, including logs, tasks, and usage.

## Jido Integration

Under the hood, agent execution uses the [Jido](https://hex.pm/packages/jido) framework for structured agent actions and workflows.
