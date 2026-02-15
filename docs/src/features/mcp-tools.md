# MCP Tools

Liteskill integrates with external tool servers using the Model Context Protocol (MCP), enabling AI models to call APIs, query databases, execute code, and interact with external services during conversations.

## What is MCP?

The Model Context Protocol (MCP) is an open standard for connecting AI models to external tools and data sources. It uses JSON-RPC 2.0 over HTTP to provide a uniform interface for tool discovery and execution. An MCP server exposes a set of tools -- each with a name, description, and input schema -- that an AI model can invoke during a conversation.

Liteskill acts as an MCP client, connecting to one or more MCP servers and making their tools available to the AI during chat sessions and agent runs.

## Connecting MCP Servers

MCP servers are registered through the Settings UI or programmatically via `McpServers.create_server/1`.

### Server Configuration

| Field | Description |
|---|---|
| `name` | Display name for the server (e.g., "Database Tools", "GitHub Actions") |
| `url` | The server's HTTP endpoint -- HTTPS required |
| `api_key` | Optional bearer token for authentication -- encrypted at rest |
| `headers` | Optional custom headers as a JSON map -- encrypted at rest |
| `description` | Human-readable description of what the server provides |
| `status` | `active` or `inactive` |
| `global` | If `true`, available to all users on the instance |

### Global vs User-Scoped Servers

- **Global servers (`global: true`)**: Visible to all users. Typically configured by administrators for shared organizational tools.
- **User-scoped servers (`global: false`)**: Only visible to the creating user, unless explicitly shared via ACLs.

Server visibility follows the same access pattern as other entities:

1. The user created the server (`user_id` matches)
2. The server is marked `global`
3. The user has been granted access via an entity ACL

## Tool Discovery

When a user selects MCP servers for a conversation, Liteskill discovers available tools via the JSON-RPC 2.0 `tools/list` method:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/list",
  "id": 1
}
```

The server responds with a list of tool definitions, each containing:

- **name** -- Unique identifier for the tool (e.g., `query_database`, `create_issue`)
- **description** -- Human-readable explanation of what the tool does
- **inputSchema** -- JSON Schema defining the expected input parameters

These tool definitions are converted to the format expected by the LLM provider (toolSpec format) and included in the LLM request so the model knows what tools are available.

## Tool Execution

When the AI model decides to use a tool, Liteskill executes it via the JSON-RPC 2.0 `tools/call` method:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "query_database",
    "arguments": {
      "query": "SELECT count(*) FROM users"
    }
  },
  "id": 1
}
```

The server processes the request and returns the result in its response body. Liteskill records the tool call as events in the event store (`ToolCallStarted` and `ToolCallCompleted`) and feeds the result back to the LLM for the next response.

## Auto-Confirm Mode

When auto-confirm is enabled for a conversation, tool calls execute automatically without user intervention:

1. The LLM returns one or more tool use requests
2. Each tool call is validated against the allowed tools list
3. Valid tools are executed immediately via their MCP server
4. Results are recorded as events and fed back to the LLM
5. The LLM generates its next response incorporating the tool results

This loop continues for up to 10 rounds (configurable) before stopping. Auto-confirm mode is ideal for trusted tools where user review is unnecessary.

## Manual Approval Mode

When auto-confirm is disabled (the default), the UI pauses at each tool call for user review:

1. The LLM returns tool use requests
2. `ToolCallStarted` events are emitted and displayed in the conversation UI
3. The stream handler subscribes to a PubSub topic and waits for user decisions
4. The UI presents each pending tool call with its name, input arguments, and approve/deny buttons
5. The user reviews each tool call and approves or denies it
6. Approved tools execute normally; denied tools return an error to the LLM
7. If no decision is made within **300 seconds** (5 minutes), all pending tool calls are automatically denied

Manual approval mode provides a safety layer for tools that perform actions with real-world consequences, such as modifying databases, sending emails, or deploying code.

## Security

MCP server connections enforce several security measures:

### HTTPS Required

All MCP server URLs must use HTTPS. HTTP URLs are rejected during validation.

### Private/Reserved IP Blocking

URLs pointing to private or reserved IP ranges are blocked to prevent Server-Side Request Forgery (SSRF):

- `localhost`, `127.x.x.x`
- `10.x.x.x` (RFC 1918)
- `172.16.x.x` - `172.31.x.x` (RFC 1918)
- `192.168.x.x` (RFC 1918)
- `169.254.x.x` (link-local)
- `0.x.x.x`
- IPv6 loopback (`::1`) and private ranges (`fc`, `fd`, `fe80`)

### Sensitive Header Blocking

Custom headers are filtered to prevent injection of security-sensitive values. The following header names are blocked:

- `authorization` (set automatically from the `api_key` field)
- `host`
- `content-type` and `content-length` (set by the client)
- `transfer-encoding` and `connection`
- `cookie` and `set-cookie`
- `x-forwarded-for`, `x-forwarded-host`, `x-forwarded-proto`
- `proxy-authorization`

Headers containing control characters (`\r`, `\n`, `\0`) in either key or value are also rejected.

## Built-in Tools

In addition to external MCP servers, Liteskill includes built-in tool suites that run in-process without HTTP calls. Built-in tools appear alongside MCP servers in the tool picker.

### Reports Tool

The Reports built-in tool provides AI agents with the ability to create and manage structured reports. It exposes tools for:

- Creating reports
- Reading report content and structure
- Modifying report sections (upsert, delete, move)
- Adding and resolving comments

This tool is used by the Agent Studio runner to produce report deliverables from pipeline executions.

## ACL Sharing

MCP servers support the same ACL sharing system used by other Liteskill entities:

- **Owner**: Full control, including editing and deletion
- **Shared access**: Read-only tool discovery and execution

Share MCP servers with specific users or make them global for the entire instance.
