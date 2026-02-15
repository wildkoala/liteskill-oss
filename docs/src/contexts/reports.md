# Reports Context

Module: `Liteskill.Reports`

Context for managing reports and their nested sections. Reports are structured documents with infinitely-nesting sections that render as markdown with `#`, `##`, `###`, etc. headers.

## Schemas

### Report

`Liteskill.Reports.Report`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `title` | `:string` | Required |
| `user_id` | `:binary_id` | Owner |

### ReportSection

`Liteskill.Reports.ReportSection`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `title` | `:string` | Section heading |
| `content` | `:string` | Section body content |
| `position` | `:integer` | Order among siblings |
| `report_id` | `:binary_id` | FK to Report |
| `parent_section_id` | `:binary_id` | FK to ReportSection (nullable for top-level) |

Sections use path notation with `>` delimiter for nested addressing: `"Parent > Child > Grandchild"`.

### SectionComment

`Liteskill.Reports.SectionComment`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `body` | `:string` | Comment text |
| `author_type` | `:string` | `"user"` or `"agent"` |
| `status` | `:string` | `"open"` or `"addressed"` |
| `section_id` | `:binary_id` | FK to ReportSection (nullable for report-level comments) |
| `report_id` | `:binary_id` | FK to Report |
| `parent_comment_id` | `:binary_id` | FK to SectionComment (for replies) |
| `user_id` | `:binary_id` | Author |

## Report CRUD

### `create_report(user_id, title)`

Creates a report with an owner ACL in a transaction.

```elixir
create_report(binary_id, String.t())
:: {:ok, Report.t()} | {:error, term()}
```

### `list_reports(user_id)`

Lists reports accessible to the user (owned or ACL-shared), ordered by most recently updated.

```elixir
list_reports(binary_id) :: [Report.t()]
```

### `get_report(report_id, user_id)`

Gets a report with sections preloaded (ordered by position), if the user has access.

```elixir
get_report(binary_id, binary_id)
:: {:ok, Report.t()} | {:error, :not_found}
```

### `delete_report(report_id, user_id)`

Deletes a report. Owner only.

```elixir
delete_report(binary_id, binary_id)
:: {:ok, Report.t()} | {:error, :not_found | :forbidden}
```

## Section Management

### `upsert_section(report_id, user_id, path, content)`

Creates or updates a section at the given path. Intermediate sections are auto-created if they do not exist.

```elixir
upsert_section(binary_id, binary_id, String.t(), String.t())
:: {:ok, ReportSection.t()} | {:error, :not_found | :invalid_path}
```

### `upsert_sections(report_id, user_id, sections)`

Batch upsert of multiple sections. Each section is a map with `path` and `content` keys.

```elixir
upsert_sections(binary_id, binary_id, [map()])
:: {:ok, [map()]} | {:error, :not_found | :invalid_path}
```

### `modify_sections(report_id, user_id, actions)`

Batch section operations. Each action is a map with an `"action"` key.

```elixir
modify_sections(binary_id, binary_id, [map()])
:: {:ok, [map()]} | {:error, term()}
```

Supported actions:
- `"upsert"` -- requires `"path"` and `"content"`
- `"delete"` -- requires `"path"`, rolls back transaction if section not found
- `"move"` -- requires `"path"` and `"position"` (integer), reorders siblings

### `update_section_content(section_id, user_id, attrs)`

Updates a section's content by section ID.

```elixir
update_section_content(binary_id, binary_id, map())
:: {:ok, ReportSection.t()} | {:error, :not_found}
```

### `delete_section(section_id, user_id)`

Deletes a section by ID.

```elixir
delete_section(binary_id, binary_id)
:: {:ok, ReportSection.t()} | {:error, :not_found}
```

## Comment Management

### `add_comment(section_id, user_id, body, author_type)`

Adds a comment to a section. `author_type` must be `"user"` or `"agent"`.

```elixir
add_comment(binary_id, binary_id, String.t(), String.t())
:: {:ok, SectionComment.t()} | {:error, :not_found | :invalid_author_type}
```

### `add_report_comment(report_id, user_id, body, author_type)`

Adds a report-level comment (not attached to a specific section).

```elixir
add_report_comment(binary_id, binary_id, String.t(), String.t())
:: {:ok, SectionComment.t()} | {:error, :not_found | :invalid_author_type}
```

### `resolve_comment(comment_id, user_id, body)`

Resolves a comment by adding an agent reply and setting the comment status to `"addressed"`. Runs in a transaction.

```elixir
resolve_comment(binary_id, binary_id, String.t())
:: {:ok, SectionComment.t()} | {:error, :not_found}
```

### `reply_to_comment(comment_id, user_id, body, author_type)`

Adds a reply to an existing comment.

```elixir
reply_to_comment(binary_id, binary_id, String.t(), String.t())
:: {:ok, SectionComment.t()} | {:error, :not_found | :invalid_author_type}
```

### `manage_comments(report_id, user_id, actions)`

Batch comment operations.

```elixir
manage_comments(binary_id, binary_id, [map()])
:: {:ok, [map()]} | {:error, term()}
```

Supported actions:
- `"add"` -- requires `"body"`, optional `"path"` (empty path = report-level comment)
- `"resolve"` -- requires `"comment_id"` and `"body"` (the resolution reply text)

### `list_section_comments(section_id, user_id)`

Lists comments for a section ordered by insertion time.

```elixir
list_section_comments(binary_id, binary_id)
:: {:ok, [SectionComment.t()]} | {:error, :not_found}
```

### `get_report_comments(report_id, user_id)`

Gets report-level comments (not attached to sections) with replies preloaded.

```elixir
get_report_comments(binary_id, binary_id)
:: {:ok, [SectionComment.t()]} | {:error, :not_found}
```

## Markdown Rendering

### `render_markdown(report, opts \\ [])`

Renders a report and its sections as a markdown string. Sections are rendered as nested headers based on depth.

```elixir
render_markdown(Report.t(), keyword()) :: String.t()
```

Options:
- `:include_comments` -- include comments in output (default: `true`). Comments are rendered as blockquotes with status labels (`[OPEN]`/`[ADDRESSED]`) and author types (`[USER]`/`[AGENT]`).
- `:start_depth` -- starting header depth (default: 1, meaning `#` for top-level)

### `section_tree(report)`

Builds a tree of sections with nested comments for a report.

```elixir
section_tree(Report.t()) :: [%{section: ReportSection.t(), children: list()}]
```

## ACL Sharing

### `grant_access(report_id, owner_id, grantee_email, role \\ "member")`

Grants access to a report by grantee email. The `"member"` role is normalized to `"manager"`.

```elixir
grant_access(binary_id, binary_id, String.t(), String.t())
:: {:ok, EntityAcl.t()} | {:error, :user_not_found | term()}
```

### `revoke_access(report_id, owner_id, target_user_id)`

```elixir
revoke_access(binary_id, binary_id, binary_id)
:: {:ok, EntityAcl.t()} | {:error, term()}
```

### `leave_report(report_id, user_id)`

```elixir
leave_report(binary_id, binary_id)
:: {:ok, EntityAcl.t()} | {:error, :owner_cannot_leave | :not_found}
```
