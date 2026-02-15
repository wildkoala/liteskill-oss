# Data Sources

Module: `Liteskill.DataSources`

Context for managing data sources and documents. Data sources can be either DB-backed (user-created) or built-in (defined in code, like Wiki). Documents are always stored in the database.

## Schemas

### Source

`Liteskill.DataSources.Source`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Required |
| `source_type` | `:string` | e.g. `"google_drive"`, `"wiki"`, `"confluence"` |
| `metadata` | `:map` | Encrypted config (credentials, folder IDs, etc.) |
| `sync_status` | `:string` | Current sync status |
| `last_synced_at` | `:utc_datetime` | |
| `last_sync_error` | `:string` | |
| `sync_cursor` | `:map` | Pagination cursor for incremental syncs |
| `sync_document_count` | `:integer` | |
| `user_id` | `:binary_id` | Owner |

### Document

`Liteskill.DataSources.Document`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `title` | `:string` | |
| `content` | `:string` | Document body |
| `slug` | `:string` | URL-friendly identifier |
| `content_hash` | `:string` | SHA-256 hash for change detection |
| `external_id` | `:string` | ID in the external system |
| `position` | `:integer` | Order among siblings |
| `source_ref` | `:string` | Source identifier (e.g. `"builtin:wiki"`, source UUID) |
| `parent_document_id` | `:binary_id` | FK to Document (for tree structures) |
| `user_id` | `:binary_id` | Owner |

## Available Source Types

- Google Drive (`"google_drive"`)
- SharePoint (`"sharepoint"`)
- Confluence (`"confluence"`)
- Jira (`"jira"`)
- GitHub (`"github"`)
- GitLab (`"gitlab"`)

Each source type has specific configuration fields (credentials, URLs, project keys, etc.) defined in `config_fields_for/1`.

## Source CRUD

### `list_sources(user_id)`

Lists sources accessible to the user: user-owned, ACL-shared, and builtin virtual sources.

```elixir
list_sources(binary_id) :: [Source.t()]
```

### `list_sources_with_counts(user_id)`

Like `list_sources/1` but includes a `:document_count` field on each source.

```elixir
list_sources_with_counts(binary_id) :: [map()]
```

### `get_source(id, user_id)`

Gets a source. Handles builtin sources (`"builtin:*"` IDs), user-owned, and ACL-shared.

```elixir
get_source(String.t(), binary_id)
:: {:ok, Source.t()} | {:error, :not_found}
```

### `create_source(attrs, user_id)`

Creates a source with owner ACL.

```elixir
create_source(map(), binary_id)
:: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
```

### `update_source(id, attrs, user_id)`

Updates a source. Cannot update builtin sources.

```elixir
update_source(String.t(), map(), binary_id)
:: {:ok, Source.t()} | {:error, :not_found | :cannot_update_builtin}
```

### `delete_source(id, user_id)`

Deletes a source and all its documents. Cannot delete builtin sources.

```elixir
delete_source(String.t(), binary_id)
:: {:ok, Source.t()} | {:error, :not_found | :cannot_delete_builtin}
```

## Document CRUD

### `list_documents(source_ref, user_id)`

Lists documents for a source, ordered by most recently updated.

```elixir
list_documents(String.t(), binary_id) :: [Document.t()]
```

### `list_documents_paginated(source_ref, user_id, opts \\ [])`

Paginated document listing with search and parent filtering. For wiki sources, includes ACL-based access for shared spaces.

```elixir
list_documents_paginated(String.t(), binary_id, keyword())
:: %{documents: [Document.t()], page: integer(), page_size: integer(), total: integer(), total_pages: integer()}
```

Options:
- `:page` -- page number (default: 1)
- `:page_size` -- items per page (default: 20)
- `:search` -- search term for title/content (ILIKE)
- `:parent_id` -- filter by parent document (`:unset` for no filter, `nil` for root docs)

### `get_document(id, user_id)`

Gets a document. For wiki documents, checks ACL access via the root space.

```elixir
get_document(binary_id, binary_id)
:: {:ok, Document.t()} | {:error, :not_found}
```

### `get_document_with_role(id, user_id)`

Returns the document along with the user's role (`"owner"` or ACL role).

```elixir
get_document_with_role(binary_id, binary_id)
:: {:ok, Document.t(), String.t()} | {:error, :not_found}
```

### `create_document(source_ref, attrs, user_id)`

Creates a document. For wiki documents (`"builtin:wiki"`), also creates a wiki space ACL.

```elixir
create_document(String.t(), map(), binary_id)
:: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
```

### `create_child_document(source_ref, parent_id, attrs, user_id)`

Creates a child document under a parent. For wiki documents, checks edit permissions against the root space. The child inherits the space owner's `user_id`.

```elixir
create_child_document(String.t(), binary_id, map(), binary_id)
:: {:ok, Document.t()} | {:error, :not_found | :forbidden}
```

### `update_document(id, attrs, user_id)`

Updates a document. For wiki documents, requires edit permission on the space.

```elixir
update_document(binary_id, map(), binary_id)
:: {:ok, Document.t()} | {:error, :not_found}
```

### `delete_document(id, user_id)`

Deletes a document. For wiki spaces (root documents), requires owner role. For wiki child pages, requires manager or owner role on the space.

```elixir
delete_document(binary_id, binary_id)
:: {:ok, Document.t()} | {:error, :not_found | :forbidden}
```

## Document Tree

### `document_tree(source_ref, user_id)`

Builds a tree of documents for a source, ordered by position.

```elixir
document_tree(String.t(), binary_id)
:: [%{document: Document.t(), children: list()}]
```

### `space_tree(source_ref, space_id, user_id)`

Builds a tree of documents within a wiki space. Handles both owned and shared spaces via ACL checks.

```elixir
space_tree(String.t(), binary_id, binary_id)
:: [%{document: Document.t(), children: list()}]
```

### `find_root_ancestor(document_id, user_id)`

Walks up the parent chain to find the root document. Checks access permissions.

```elixir
find_root_ancestor(binary_id, binary_id)
:: {:ok, Document.t()} | {:error, :not_found}
```

### `get_space_id(document)`

Returns the root space ID for a wiki document by walking up the parent chain.

```elixir
get_space_id(Document.t()) :: binary_id | nil
```

## Sync Pipeline

### `start_sync(source_id, user_id)`

Enqueues an Oban `SyncWorker` job to sync a data source.

```elixir
start_sync(binary_id, binary_id)
:: {:ok, Oban.Job.t()} | {:error, term()}
```

### `upsert_document_by_external_id(source_ref, external_id, attrs, user_id)`

Creates or updates a document by its external ID. Uses content hash for change detection. Returns `{:ok, :created | :updated | :unchanged, document}`.

```elixir
upsert_document_by_external_id(String.t(), String.t(), map(), binary_id)
:: {:ok, :created | :updated | :unchanged, Document.t()} | {:error, term()}
```

### `delete_document_by_external_id(source_ref, external_id, user_id)`

Deletes a document by its external ID.

```elixir
delete_document_by_external_id(String.t(), String.t(), binary_id)
:: {:ok, :not_found | Document.t()} | {:error, term()}
```

### `update_sync_status(source, status, error \\ nil)`

Updates a source's sync status. Sets `last_synced_at` when status is `"complete"`.

### `update_sync_cursor(source, cursor, document_count)`

Updates a source's sync cursor and document count for incremental syncs.

### `export_report_to_wiki(report_id, user_id, opts \\ [])`

Exports a report's markdown content as a wiki document.

Options:
- `:title` -- wiki page title (defaults to report title)
- `:parent_id` -- parent document ID for nesting

## Connector Interface

### Connector Behaviour

`Liteskill.DataSources.Connector`

Each external source type implements this behaviour:

```elixir
@callback list_entries(source, cursor, keyword()) :: {:ok, list_result()} | {:error, term()}
@callback fetch_content(source, external_id, keyword()) :: {:ok, fetch_result()} | {:error, term()}
@callback validate_connection(source, keyword()) :: :ok | {:error, term()}
@callback source_type() :: String.t()
```

Types:
- `file_entry` -- `%{external_id, title, content_type, metadata, parent_external_id, content_hash, deleted}`
- `fetch_result` -- `%{content, content_type, content_hash, metadata}`
- `list_result` -- `%{entries, next_cursor, has_more}`

### ConnectorRegistry

`Liteskill.DataSources.ConnectorRegistry`

Maps source type strings to connector modules.

```elixir
ConnectorRegistry.get("google_drive") :: {:ok, Connectors.GoogleDrive}
ConnectorRegistry.get("wiki") :: {:ok, Connectors.Wiki}
ConnectorRegistry.all() :: [{"wiki", Connectors.Wiki}, ...]
```

### Built-in Connectors

- `Liteskill.DataSources.Connectors.GoogleDrive` -- Google Drive integration via service account
- `Liteskill.DataSources.Connectors.Wiki` -- Internal wiki connector

## Oban Workers

### SyncWorker

`Liteskill.DataSources.SyncWorker` -- orchestrates the sync pipeline for a data source. Resolves the connector, calls `list_entries` with cursor-based pagination, and delegates content fetching to `DocumentSyncWorker`.

### DocumentSyncWorker

`Liteskill.DataSources.DocumentSyncWorker` -- fetches and processes individual documents. Called by `SyncWorker` for each changed entry.

### ContentExtractor

`Liteskill.DataSources.ContentExtractor` -- extracts text content from various document types and formats for storage and embedding.

## Metadata Validation

### `validate_metadata(source_type, metadata)`

Validates metadata keys against the allowed config fields for the given source type. Returns filtered map with unknown keys stripped.

```elixir
validate_metadata(String.t(), map())
:: {:ok, map()} | {:error, :unknown_source_type}
```

### `config_fields_for(source_type)`

Returns the list of configuration field definitions for a source type.

```elixir
config_fields_for(String.t()) :: [%{key: String.t(), label: String.t(), placeholder: String.t(), type: atom()}]
```
