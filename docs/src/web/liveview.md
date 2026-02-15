# LiveView Architecture

Liteskill uses Phoenix LiveView as the primary UI layer. A single `ChatLive` module serves as the central router for all authenticated user interactions, delegating to specialized sub-modules for different feature areas.

## ChatLive

Module: `LiteskillWeb.ChatLive`

`ChatLive` is the main LiveView that handles all authenticated routes in the `:chat` and `:admin` live sessions. It mounts a large set of state variables (80+) and uses `apply_action/3` to configure the socket based on the current `live_action`.

### Mount State

On mount, `ChatLive` initializes state for:

- **Conversations**: list of user conversations, current conversation, messages
- **Streaming**: streaming status, stream content, stream task PID, stream errors
- **MCP Servers**: server list, forms, tool picker, auto-confirm setting, pending tool calls
- **Data Sources**: source list, current source, documents, search, RAG query state
- **Sharing**: sharing modal state, ACLs, user search
- **LLM Models**: available models, selected model ID (based on user preference)
- **UI State**: sidebar visibility, delete confirmations, modals
- **Conversations Management**: pagination, search, bulk selection
- **Edit Message**: editing state, server selection for re-generation

### Sub-Modules

`ChatLive` delegates rendering and event handling to these sub-modules:

| Module | Purpose |
|--------|---------|
| `ProfileLive` | User settings (info tab, password tab) |
| `AdminLive` | Admin panel: usage analytics, user/group/provider/model management |
| `WikiLive` | Wiki document browser and editor |
| `PipelineLive` | RAG pipeline statistics and management |
| `AgentStudioLive` | Agent, team, run, and schedule management |
| `ReportsLive` | Report generation and viewing |

Each sub-module provides:
- An `*_assigns/0` function that returns default assigns for mount
- An `apply_*_action/3` function for handling relevant live actions
- Event handlers that `ChatLive` delegates to

### Component Modules

Rendering is split across component modules:

| Module | Purpose |
|--------|---------|
| `ChatComponents` | Conversation list, message rendering, chat input, streaming UI |
| `McpComponents` | MCP server management, tool picker, tool call modals |
| `SharingComponents` | Access control UI, user search, group sharing |
| `SourcesComponents` | Data source browser, document viewer, RAG query panel |
| `WikiComponents` | Wiki navigation tree, document display, editor |
| `ReportComponents` | Report listing and detail views |
| `PipelineComponents` | Pipeline statistics, charts, source breakdown |
| `AgentStudioComponents` | Agent/team/run/schedule UI components |

## Other LiveViews

### AuthLive

Module: `LiteskillWeb.AuthLive`

Handles public authentication views:
- `:login` -- Email/password login form, OIDC provider button
- `:register` -- New user registration (when registration is open)
- `:invite` -- Invitation-based registration via token

Uses the `:redirect_if_authenticated` hook to send logged-in users to `/`.

### SetupLive

Module: `LiteskillWeb.SetupLive`

A multi-step first-time admin setup wizard with three steps:

1. **Password** (`:password`): Set the initial admin password (minimum 12 characters)
2. **Data Sources** (`:data_sources`): Select data sources to enable
3. **Configure Source** (`:configure_source`): Configure each selected data source with required credentials

Uses the `:require_setup_needed` hook, which only allows access when the admin account has `setup_required?` set to true.

### ProfileLive

Module: `LiteskillWeb.ProfileLive`

User settings rendered within `ChatLive`:
- `:info` -- Display name, email, avatar, accent color preferences
- `:password` -- Password change (required if `force_password_change` is set)

### AdminLive

Module: `LiteskillWeb.AdminLive`

Admin panel rendered within `ChatLive`:
- `:admin_usage` -- Usage analytics and spend tracking
- `:admin_servers` -- MCP server management (global servers)
- `:admin_users` -- User management (roles, invitations)
- `:admin_groups` -- Group management
- `:admin_providers` -- LLM provider configuration (API keys, endpoints)
- `:admin_models` -- LLM model management (pricing, availability)

### AgentStudioLive

Module: `LiteskillWeb.AgentStudioLive`

Agent automation features rendered within `ChatLive`:
- `:agents` / `:agent_new` / `:agent_show` / `:agent_edit` -- Agent CRUD
- `:teams` / `:team_new` / `:team_show` / `:team_edit` -- Team CRUD
- `:runs` / `:run_new` / `:run_show` / `:run_log_show` -- Run execution and logs
- `:schedules` / `:schedule_new` / `:schedule_show` -- Scheduled runs

### PipelineLive

Module: `LiteskillWeb.PipelineLive`

RAG pipeline statistics and management rendered within `ChatLive`:
- `:pipeline` -- Pipeline overview with chunk distribution charts

### ReportsLive

Module: `LiteskillWeb.ReportsLive`

Report generation rendered within `ChatLive`:
- `:reports` -- Report listing
- `:report_show` -- Individual report view

### WikiLive

Module: `LiteskillWeb.WikiLive`

Wiki document browser and editor rendered within `ChatLive`:
- `:wiki` -- Wiki document tree and browser
- `:wiki_page_show` -- Individual wiki document view/edit

## JavaScript Hooks

Defined in `assets/js/app.js`, hooks bridge LiveView server events with client-side DOM behavior.

### SidebarNav

Handles navigation events and accent color persistence:
- Listens for `"nav"` events to auto-close sidebar on mobile (viewport < 640px)
- Handles `"set-accent"` events to persist the user's accent color choice in `localStorage` and apply the `data-accent` attribute to the document root

### ScrollBottom

Auto-scrolls the message container and provides RAG citation hover highlighting:
- Uses `MutationObserver` to detect new content and auto-scroll when the user is near the bottom (within 100px)
- Sets up `mouseenter`/`mouseleave` event delegation for `.rag-cite` elements to highlight corresponding `.source-item` entries in the sources sidebar

### CopyCode

Adds clipboard copy buttons to all `<pre>` code blocks:
- Dynamically inserts a copy button into each `<pre>` element
- Uses `navigator.clipboard.writeText` for copying
- Shows a checkmark icon for 2 seconds after successful copy

### DownloadMarkdown

Handles file download events:
- Listens for `"download_markdown"` events with `filename` and `content` parameters
- Creates a `Blob` with `text/markdown` MIME type and triggers a browser download

### PipelineChart

Chart.js integration for pipeline statistics:
- Dynamically imports Chart.js from CDN
- Renders a pie chart showing chunk distribution across data sources
- Handles `"pipeline_chart_update"` events to update chart data without re-rendering

### TextareaAutoResize

Auto-growing textarea with Enter key submission:
- Adjusts textarea height on input to fit content
- Pressing Enter without Shift submits the parent form
- Pressing Shift+Enter inserts a newline

### SectionEditor / WikiEditor

CodeMirror-based editors imported from `assets/js/codemirror_hook.js` for wiki content editing.

## Styling

Liteskill uses **Tailwind CSS v4** with **daisyUI** for component styling:

- **No `tailwind.config.js`** -- Tailwind v4 uses `@import "tailwindcss"` syntax in `assets/css/app.css`
- **Theme switching**: Dark and light themes via the `data-theme` attribute on the HTML element
- **Accent colors**: 10 accent color variants controlled by the `data-accent` attribute, persisted in `localStorage`
- **Responsive**: Mobile-first design with sidebar collapse on small viewports

Co-located hooks are also supported via the `phoenix-colocated` package, merged with the custom hooks at LiveSocket initialization.
