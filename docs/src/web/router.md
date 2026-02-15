# Router

Module: `LiteskillWeb.Router`

The router defines all HTTP and LiveView routes for the application, organized into pipelines and scopes that enforce authentication, authorization, and content negotiation.

## Pipelines

### `:browser`

The standard browser pipeline for HTML requests and LiveView connections.

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {LiteskillWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end
```

Provides session management, CSRF protection, flash messages, and the root layout for all browser-based routes.

### `:api`

The API pipeline for JSON endpoints.

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug :fetch_session
  plug LiteskillWeb.Plugs.Auth, :fetch_current_user
  plug LiteskillWeb.Plugs.RateLimiter, limit: 1000, window_ms: 60_000
end
```

Accepts JSON only, loads the current user from the session, and applies rate limiting at 1000 requests per 60 seconds per client.

### `:require_auth`

An additional pipeline that enforces authentication for API routes.

```elixir
pipeline :require_auth do
  plug LiteskillWeb.Plugs.Auth, :require_authenticated_user
end
```

Returns a 401 JSON response if no authenticated user is present. Applied on top of the `:api` pipeline for protected endpoints.

## Route Structure

### Auth Routes (`/auth`)

Session management and authentication endpoints:

| Method | Path | Controller | Description |
|--------|------|------------|-------------|
| GET | `/auth/session` | `SessionController.create` | Session bridge -- exchanges signed token for session cookie |
| DELETE | `/auth/logout` | `SessionController.delete` | Clears the session and redirects to login |
| POST | `/auth/register` | `PasswordAuthController.register` | Password registration (API pipeline) |
| POST | `/auth/login` | `PasswordAuthController.login` | Password login (API pipeline) |
| GET | `/auth/:provider` | `AuthController.request` | OIDC provider redirect |
| GET | `/auth/:provider/callback` | `AuthController.callback` | OIDC callback (GET) |
| POST | `/auth/:provider/callback` | `AuthController.callback` | OIDC callback (POST) |

### LiveView Sessions

LiveView routes are grouped into named sessions, each with specific `on_mount` hooks that control access.

#### `:auth` -- Public Authentication Views

Hook: `{LiveAuth, :redirect_if_authenticated}` -- redirects already-authenticated users to `/`.

| Path | LiveView | Action |
|------|----------|--------|
| `/login` | `AuthLive` | `:login` |
| `/register` | `AuthLive` | `:register` |
| `/invite/:token` | `AuthLive` | `:invite` |

#### `:setup` -- First-Time Admin Setup

Hook: `{LiveAuth, :require_setup_needed}` -- only accessible when the admin account requires initial setup.

| Path | LiveView | Action |
|------|----------|--------|
| `/setup` | `SetupLive` | default |

#### `:admin` -- Admin Routes

Hook: `{LiveAuth, :require_admin}` -- requires the authenticated user to have admin privileges.

| Path | LiveView | Action |
|------|----------|--------|
| `/admin` | `ChatLive` | `:admin_usage` |
| `/admin/usage` | `ChatLive` | `:admin_usage` |
| `/admin/servers` | `ChatLive` | `:admin_servers` |
| `/admin/users` | `ChatLive` | `:admin_users` |
| `/admin/groups` | `ChatLive` | `:admin_groups` |
| `/admin/providers` | `ChatLive` | `:admin_providers` |
| `/admin/models` | `ChatLive` | `:admin_models` |

#### `:chat` -- Main Authenticated Routes

Hook: `{LiveAuth, :require_authenticated}` -- requires a logged-in user, redirects to `/setup` if setup is needed, and enforces password change requirements.

| Path | LiveView | Action |
|------|----------|--------|
| `/` | `ChatLive` | `:index` |
| `/conversations` | `ChatLive` | `:conversations` |
| `/c/:conversation_id` | `ChatLive` | `:show` |
| `/profile` | `ChatLive` | `:info` |
| `/profile/password` | `ChatLive` | `:password` |
| `/wiki` | `ChatLive` | `:wiki` |
| `/wiki/:document_id` | `ChatLive` | `:wiki_page_show` |
| `/sources` | `ChatLive` | `:sources` |
| `/sources/pipeline` | `ChatLive` | `:pipeline` |
| `/sources/:source_id` | `ChatLive` | `:source_show` |
| `/sources/:source_id/:document_id` | `ChatLive` | `:source_document_show` |
| `/mcp` | `ChatLive` | `:mcp_servers` |
| `/reports` | `ChatLive` | `:reports` |
| `/reports/:report_id` | `ChatLive` | `:report_show` |
| `/agents` | `ChatLive` | `:agents` |
| `/agents/new` | `ChatLive` | `:agent_new` |
| `/agents/:agent_id` | `ChatLive` | `:agent_show` |
| `/agents/:agent_id/edit` | `ChatLive` | `:agent_edit` |
| `/teams` | `ChatLive` | `:teams` |
| `/teams/new` | `ChatLive` | `:team_new` |
| `/teams/:team_id` | `ChatLive` | `:team_show` |
| `/teams/:team_id/edit` | `ChatLive` | `:team_edit` |
| `/runs` | `ChatLive` | `:runs` |
| `/runs/new` | `ChatLive` | `:run_new` |
| `/runs/:run_id` | `ChatLive` | `:run_show` |
| `/runs/:run_id/logs/:log_id` | `ChatLive` | `:run_log_show` |
| `/schedules` | `ChatLive` | `:schedules` |
| `/schedules/new` | `ChatLive` | `:schedule_new` |
| `/schedules/:schedule_id` | `ChatLive` | `:schedule_show` |

### API Routes (`/api`)

All API routes go through the `:api` and `:require_auth` pipelines, requiring an authenticated session and enforcing rate limiting.

**Conversation endpoints:**

| Method | Path | Action |
|--------|------|--------|
| GET | `/api/conversations` | `ConversationController.index` |
| POST | `/api/conversations` | `ConversationController.create` |
| GET | `/api/conversations/:id` | `ConversationController.show` |
| POST | `/api/conversations/:conversation_id/messages` | `ConversationController.send_message` |
| POST | `/api/conversations/:conversation_id/fork` | `ConversationController.fork` |
| POST | `/api/conversations/:conversation_id/acls` | `ConversationController.grant_access` |
| DELETE | `/api/conversations/:conversation_id/acls/:target_user_id` | `ConversationController.revoke_access` |
| DELETE | `/api/conversations/:conversation_id/membership` | `ConversationController.leave` |

**Group endpoints:**

| Method | Path | Action |
|--------|------|--------|
| GET | `/api/groups` | `GroupController.index` |
| POST | `/api/groups` | `GroupController.create` |
| GET | `/api/groups/:id` | `GroupController.show` |
| DELETE | `/api/groups/:id` | `GroupController.delete` |
| POST | `/api/groups/:group_id/members` | `GroupController.add_member` |
| DELETE | `/api/groups/:group_id/members/:user_id` | `GroupController.remove_member` |

### Dev Routes

Available only when `dev_routes: true` is configured (development environment):

| Path | Description |
|------|-------------|
| `/dev/dashboard` | Phoenix LiveDashboard with telemetry metrics |
| `/dev/mailbox` | Swoosh mailbox preview for local email testing |
