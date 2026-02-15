# Reports

Reports are structured documents with infinitely nested sections, a comment system with resolution workflows, and markdown rendering. They serve as the primary deliverable format for Agent Studio pipeline runs and can also be created and edited independently.

## Document Structure

A report consists of a title and a tree of sections. Each section has a title, optional content, a position within its parent, and can contain any number of child sections.

### Reports

| Field | Description |
|---|---|
| `title` | Report title |
| `user_id` | Owner of the report |

### Sections

| Field | Description |
|---|---|
| `title` | Section heading |
| `content` | Markdown content body |
| `position` | Order among siblings (0-indexed) |
| `parent_section_id` | Reference to parent section (null for top-level) |
| `report_id` | The report this section belongs to |

The section hierarchy can nest to arbitrary depth. Sections are stored as a flat table with `parent_section_id` references, then assembled into a tree for rendering.

## Section Path Notation

Sections are addressed using "path > notation" where `>` separates hierarchy levels:

```
Overview
Stage 1: Analyst (lead) > Configuration
Stage 1: Analyst (lead) > Analysis
Stage 1: Analyst (lead) > Output
Pipeline Summary
Conclusion
```

For example, the path `"Stage 1: Analyst (lead) > Configuration"` refers to a section titled "Configuration" that is a child of a section titled "Stage 1: Analyst (lead)".

When upserting with a path, the system walks the hierarchy and creates any missing parent sections along the way. If the target section already exists at that path, its content is updated.

## Section Operations

### Upsert

`Reports.upsert_section/4` creates or updates a section at a given path:

- If the section exists at the specified path, its content is updated
- If the section does not exist, it is created with the next available position among its siblings
- Parent sections in the path are created automatically if they do not exist

### Modify Sections (Batch)

`Reports.modify_sections/3` performs multiple section operations in a single database transaction. Each action in the list specifies an operation:

**upsert** -- Create or update a section:
```elixir
%{"action" => "upsert", "path" => "Parent > Child", "content" => "New content"}
```

**delete** -- Remove a section and its children:
```elixir
%{"action" => "delete", "path" => "Parent > Child"}
```

**move** -- Reposition a section among its siblings:
```elixir
%{"action" => "move", "path" => "Parent > Child", "position" => 0}
```

The move operation reorders all siblings to accommodate the new position. Positions are clamped to valid range.

### Update and Delete

Individual sections can also be updated via `Reports.update_section_content/3` or deleted via `Reports.delete_section/2`. Both operations require the user to have access to the parent report.

## Comments

Reports include a comment system that supports section-level and report-level comments, replies, and a resolution workflow.

### Comment Fields

| Field | Description |
|---|---|
| `body` | Comment text content |
| `author_type` | `user` or `agent` |
| `status` | `open` or `addressed` |
| `section_id` | The section this comment is on (null for report-level comments) |
| `report_id` | The report this comment belongs to |
| `parent_comment_id` | Reference to parent comment for replies |

### Adding Comments

Comments can be added at two levels:

- **Section comments**: `Reports.add_comment/4` -- attached to a specific section
- **Report comments**: `Reports.add_report_comment/4` -- attached to the report as a whole

Both require specifying the `author_type` as either `"user"` or `"agent"`.

### Replies

Reply to any comment using `Reports.reply_to_comment/4`. Replies are linked to their parent via `parent_comment_id` and inherit the same section and report associations.

### Resolution Workflow

Comments follow an `open` to `addressed` lifecycle:

1. A comment starts with status `open`
2. Call `Reports.resolve_comment/3` with the comment ID, user ID, and a resolution body
3. The system creates a reply from the `"agent"` author type containing the resolution text
4. The original comment's status is updated to `addressed`

This workflow is designed for the AI agent loop: users leave comments on report sections, and the AI agent reads them, makes edits, and resolves the comments by explaining what changed.

### Manage Comments (Batch)

`Reports.manage_comments/3` performs multiple comment operations in a single transaction:

**add** -- Add a comment to a section or report:
```elixir
%{"action" => "add", "path" => "Section Title", "body" => "Please expand this section"}
```

If `path` is empty, the comment is added at the report level.

**resolve** -- Resolve an existing comment:
```elixir
%{"action" => "resolve", "comment_id" => "uuid", "body" => "Expanded the section with more detail"}
```

## Markdown Rendering

`Reports.render_markdown/2` renders a report as a markdown document. The rendering process:

1. Loads all sections ordered by position
2. Builds a tree from the flat section list
3. Renders each section as a markdown heading (`#`, `##`, `###`, etc.) based on depth
4. Includes section content below each heading
5. Optionally includes comments as blockquotes

### Comment Rendering

When `include_comments: true` (the default), comments are rendered as blockquotes within their sections:

```markdown
> **[USER] [OPEN] (id:abc123)**: This section needs more detail
>> **[AGENT] (reply)**: I've expanded the analysis with additional data points
```

The format includes:
- Author type label (`[USER]` or `[AGENT]`)
- Status label (`[OPEN]` or `[ADDRESSED]`)
- Comment ID for reference
- Nested replies with `>>` blockquote prefix

Pass `include_comments: false` to render a clean document without comment annotations.

### Start Depth

The `start_depth` option (default 1) controls the heading level for top-level sections. With `start_depth: 1`, top-level sections render as `# Heading`. With `start_depth: 2`, they render as `## Heading`.

## ACL Sharing

Reports support ACL-based sharing with owner and member roles:

- **Owner**: Full control including deletion, section management, and granting/revoking access
- **Member** (normalized to `manager`): Can view the report, edit sections, and manage comments

Share reports with specific users via `Reports.grant_access/4` using their email address. Access can be revoked by the owner or voluntarily relinquished by the user.

## Reports as Agent Studio Deliverables

Reports are the primary output format for Agent Studio pipeline runs. When a run executes:

1. The runner creates a new report titled `"Run Name -- Agent1, Agent2, ..."`
2. Each pipeline stage writes Configuration, Analysis, and Output sections
3. The runner appends Pipeline Summary and Conclusion sections
4. The report ID is stored in the run's `deliverables` map

Users can then view, edit, comment on, and share the resulting report through the Reports UI. Reports can also be exported to Wiki pages via `DataSources.export_report_to_wiki/3`.
