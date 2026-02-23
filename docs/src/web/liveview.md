# LiveView

Liteskill's UI is built entirely with Phoenix LiveView. The main interface is a single `ChatLive` module that renders different views based on the route's live action.

## Live Sessions

The router defines several live sessions with different auth requirements:

| Session | Mount Hook | Purpose |
|---------|-----------|---------|
| `:auth` | `redirect_if_authenticated` | Login/register (redirects away if already logged in) |
| `:setup` | `require_setup_needed` | First-time admin setup |
| `:admin` | `require_admin` | Admin-only routes |
| `:chat` | `require_authenticated` | All authenticated user routes |

## ChatLive

`ChatLive` is the primary LiveView module. It uses the live action to determine which view to render:

- `:index` / `:conversations` / `:show` — Chat interface
- `:admin_*` — Admin panels
- `:settings_*` — Single-user mode settings
- `:mcp_servers` — MCP server management
- `:reports` / `:report_show` — Reports
- `:agent_studio` / `:agents` / `:agent_show` — Agent studio
- `:teams` / `:team_show` — Teams
- `:runs` / `:run_show` — Runs
- `:schedules` / `:schedule_show` — Schedules
- `:sources` / `:source_show` — Data sources

## WikiLive

A separate `WikiLive` module handles the wiki interface at `/wiki`.

## Auth Hooks

`LiteskillWeb.Plugs.LiveAuth` provides `on_mount` callbacks:

- `:require_authenticated` — Redirects to `/login` if not authenticated
- `:redirect_if_authenticated` — Redirects to `/` if already logged in
- `:require_admin` — Requires admin role
- `:require_setup_needed` — Only allows access during initial setup

## Real-Time Updates

LiveView receives real-time updates via PubSub:

- **Streaming chunks** — LLM response chunks update the UI in real-time
- **Tool call status** — Tool call progress and results
- **Run updates** — Agent run status and log entries
