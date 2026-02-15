# MCP Servers Context

Module: `Liteskill.McpServers`

The McpServers context manages MCP (Model Context Protocol) server registrations. MCP servers provide tool capabilities to LLM conversations via JSON-RPC 2.0 over HTTP (Streamable HTTP transport).

## McpServer Schema

`Liteskill.McpServers.McpServer`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Required |
| `url` | `:string` | HTTPS required, no private/reserved IPs |
| `api_key` | `:string` | Encrypted at rest |
| `description` | `:string` | |
| `headers` | `:map` | Encrypted at rest, custom HTTP headers |
| `status` | `:string` | Server status |
| `global` | `:boolean` | If true, available to all users |
| `user_id` | `:binary_id` | Owner |

### Security

- HTTPS is required for all server URLs
- Private and reserved IP addresses are blocked
- Sensitive headers are blocked (authorization, host, cookie, proxy-authorization, etc.)

## Context API

### `list_servers(user_id)`

Lists MCP servers accessible to the user: user-owned, global, ACL-shared, and builtin virtual servers (prefixed with `"builtin:"`).

```elixir
list_servers(binary_id) :: [McpServer.t()]
```

### `get_server(id, user_id)`

Gets an MCP server if accessible to the user. Handles builtin servers (`"builtin:*"` IDs), user-owned servers, global servers, and ACL-shared servers.

```elixir
get_server(String.t(), binary_id)
:: {:ok, McpServer.t()} | {:error, :not_found}
```

### `create_server(attrs)`

Creates an MCP server and auto-creates an owner ACL.

```elixir
create_server(map())
:: {:ok, McpServer.t()} | {:error, Ecto.Changeset.t()}
```

### `update_server(server, user_id, attrs)`

Updates an MCP server. Owner only.

```elixir
update_server(McpServer.t(), binary_id, map())
:: {:ok, McpServer.t()} | {:error, :forbidden | Ecto.Changeset.t()}
```

### `delete_server(id, user_id)`

Deletes an MCP server. Owner only.

```elixir
delete_server(binary_id, binary_id)
:: {:ok, McpServer.t()} | {:error, :not_found | :forbidden}
```

## MCP Client

Module: `Liteskill.McpServers.Client`

HTTP client for MCP JSON-RPC 2.0 communication using Streamable HTTP transport.

### `list_tools(server, opts \\ [])`

Discovers tools from an MCP server by calling the `tools/list` method. Returns a list of tool descriptors.

```elixir
list_tools(McpServer.t(), keyword())
:: {:ok, [map()]} | {:error, term()}
```

Each tool map contains:
- `"name"` -- tool name
- `"description"` -- tool description
- `"inputSchema"` -- JSON Schema for the tool's input parameters

Options:
- `:plug` -- Req test plug (for testing with `Req.Test`)

### `call_tool(server, tool_name, arguments, opts \\ [])`

Calls a tool on an MCP server via the `tools/call` method.

```elixir
call_tool(McpServer.t(), String.t(), map(), keyword())
:: {:ok, map()} | {:error, term()}
```

Options:
- `:plug` -- Req test plug (for testing with `Req.Test`)

### Header Construction

The client builds headers in this order:
1. `content-type: application/json` and `accept: application/json, text/event-stream`
2. `authorization: Bearer <api_key>` (if the server has an API key configured)
3. Custom headers from the server's `headers` map (with blocked headers filtered out)

Blocked headers: `authorization`, `host`, `content-type`, `content-length`, `transfer-encoding`, `connection`, `cookie`, `set-cookie`, `x-forwarded-for`, `x-forwarded-host`, `x-forwarded-proto`, `proxy-authorization`

Headers containing control characters (`\r`, `\n`, `\0`) in keys or values are also rejected.
