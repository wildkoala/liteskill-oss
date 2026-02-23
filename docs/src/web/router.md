# Router

`LiteskillWeb.Router` defines all routes for the application. Routes are organized into scopes with different pipelines.

## Pipelines

| Pipeline | Purpose |
|----------|---------|
| `:browser` | HTML requests with session, CSRF, LiveView flash |
| `:api` | JSON requests with session, auth, and rate limiting (1000 req/min) |
| `:require_auth` | Requires authenticated user |

## Auth Routes (`/auth`)

| Route | Description |
|-------|-------------|
| `GET /auth/session` | Session bridge for LiveView auth |
| `DELETE /auth/logout` | Logout |
| `GET /auth/openrouter` | OpenRouter OAuth PKCE start |
| `GET /auth/openrouter/callback` | OpenRouter OAuth callback |
| `POST /auth/register` | Password registration (API) |
| `POST /auth/login` | Password login (API) |
| `GET /auth/:provider` | OIDC provider redirect |
| `GET /auth/:provider/callback` | OIDC callback |

## Public LiveView Routes

| Route | Description |
|-------|-------------|
| `/login` | Login page |
| `/register` | Registration page |
| `/invite/:token` | Invitation acceptance |
| `/setup` | First-time admin setup |

## Authenticated LiveView Routes

### Chat
| Route | Description |
|-------|-------------|
| `/` | Main chat interface |
| `/conversations` | Conversation list |
| `/c/:conversation_id` | Single conversation |

### Profile
| Route | Description |
|-------|-------------|
| `/profile` | User info |
| `/profile/password` | Password change |
| `/profile/providers` | User LLM providers |
| `/profile/models` | User LLM models |

### Settings (Single-User Mode)
| Route | Description |
|-------|-------------|
| `/settings` | Settings overview |
| `/settings/general` | General settings |
| `/settings/providers` | Provider management |
| `/settings/models` | Model management |
| `/settings/rag` | RAG settings |
| `/settings/account` | Account settings |

### Features
| Route | Description |
|-------|-------------|
| `/wiki`, `/wiki/:document_id` | Wiki |
| `/sources`, `/sources/:source_id` | Data sources |
| `/mcp` | MCP servers |
| `/reports`, `/reports/:report_id` | Reports |
| `/agents`, `/agents/:agent_id` | Agent studio |
| `/teams`, `/teams/:team_id` | Teams |
| `/runs`, `/runs/:run_id` | Runs |
| `/schedules`, `/schedules/:schedule_id` | Schedules |

## Admin Routes (`/admin`)

Requires admin role via `LiveAuth :require_admin`.

| Route | Description |
|-------|-------------|
| `/admin/usage` | Usage dashboard |
| `/admin/servers` | MCP server management |
| `/admin/users` | User management |
| `/admin/groups` | Group management |
| `/admin/providers` | LLM provider management |
| `/admin/models` | LLM model management |
| `/admin/roles` | RBAC role management |
| `/admin/rag` | RAG admin settings |
| `/admin/setup` | Admin setup |

## REST API (`/api`)

Requires authentication. See the [API](api.md) page for details.

## Dev Routes

Available only in development:

- `/dev/dashboard` — Phoenix LiveDashboard
- `/dev/mailbox` — Swoosh email preview
