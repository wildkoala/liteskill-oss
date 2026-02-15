# Wiki

Liteskill includes a built-in wiki system for collaborative documentation. Wiki spaces let teams create, organize, and share knowledge bases with markdown support, hierarchical document organization, and automatic RAG integration.

## Wiki Spaces

Wiki spaces are the top-level containers for collaborative documentation. Each wiki space is a document with `source_ref: "builtin:wiki"` and no parent (`parent_document_id: nil`). Spaces serve as the root of a document tree and as the anchor for access control.

When you create a wiki space, the system automatically creates an owner ACL entry for the entity type `"wiki_space"`. This ACL governs who can view and edit all documents within the space.

## Document Creation and Editing

### Creating Documents

Wiki documents are created through the DataSources context:

- **Root spaces**: `DataSources.create_document("builtin:wiki", attrs, user_id)` creates a new wiki space owned by the user
- **Child pages**: `DataSources.create_child_document("builtin:wiki", parent_id, attrs, user_id)` creates a page within an existing space

Child pages are automatically assigned the next available position under their parent. For shared wiki spaces, child pages are created under the space owner's user ID (not the editing user's), maintaining consistent ownership within the space.

### Editing Documents

Documents support markdown content editing via `DataSources.update_document/3`. The system checks access permissions:

- The document owner can always edit
- For wiki documents in shared spaces, users with `manager` or `owner` roles on the wiki space can edit

### Document Fields

| Field | Description |
|---|---|
| `title` | Page title |
| `content` | Markdown content |
| `slug` | URL-friendly identifier |
| `content_type` | Content format (default: markdown) |
| `position` | Order among siblings |
| `parent_document_id` | Reference to parent page (null for spaces) |
| `source_ref` | Always `"builtin:wiki"` for wiki documents |
| `external_id` | External identifier for sync operations |
| `metadata` | Additional metadata as JSON |

## Access Control

Wiki access control operates at the space level through the `wiki_space` entity type in the ACL system.

### Roles

- **Owner**: Full control over the space, including deletion and access management
- **Manager**: Can create, edit, and delete child pages within the space
- **Member**: Can view all documents in the space

### Permission Checks

Access is determined by walking up the document tree to find the root space, then checking the ACL:

1. If the user owns the document, access is granted
2. Otherwise, the system finds the root ancestor (the wiki space)
3. It checks whether the user has an ACL entry for that space
4. For editing, the role must be `manager` or `owner`
5. For deleting child pages, the role must be `manager` or `owner`
6. For deleting the space itself, the role must be `owner`

### Sharing Spaces

Share a wiki space with other users using the standard ACL mechanisms. Shared spaces appear in the collaborator's document list alongside their own spaces.

## Document Hierarchy

Wiki documents are organized in a tree structure. Each document can have child documents, enabling nested organization like:

```
Wiki Space (root)
  |-- Getting Started
  |   |-- Installation
  |   |-- Configuration
  |-- Architecture
  |   |-- Overview
  |   |-- Data Model
  |-- API Reference
```

### Tree Display

The `DataSources.space_tree/3` function builds the document tree for a wiki space, returning a nested structure of documents and their children. For shared spaces, the tree is built from the space owner's documents, respecting ACL permissions.

The `DataSources.document_tree/2` function returns the complete tree for a source, useful for navigation sidebars.

### Root Ancestor Resolution

`DataSources.find_root_ancestor/2` walks up the parent chain to find the root wiki space for any document. This is used to determine which ACL governs access to a given page. The resolution is depth-limited to 100 levels to prevent infinite loops.

## RAG Integration (Wiki Sync)

Wiki content is automatically synchronized to the RAG vector store via the `WikiSyncWorker`. When a wiki document is created or updated, the system:

1. Finds or creates a "Wiki" collection and "wiki" source for the user
2. Removes any existing RAG document for the wiki page
3. Creates a new RAG document with metadata linking back to the wiki document and space
4. Chunks the content using the recursive text splitter
5. Generates embeddings via Cohere embed-v4 on Bedrock
6. Stores the chunks with their embeddings in the vector store

When a wiki document is deleted, the corresponding RAG document and its chunks are also removed.

This integration means wiki content is automatically searchable in chat conversations through the RAG pipeline. The metadata includes `wiki_document_id` and `wiki_space_id` for ACL-aware search results.

### Wiki Source Connector

The wiki source connector (`DataSources.Connectors.Wiki`) implements the `Connector` behaviour for the built-in wiki source. It provides:

- **`list_entries/3`** -- Lists all wiki documents as sync entries with their content hashes
- **`fetch_content/3`** -- Retrieves a specific wiki document's content
- **`validate_connection/2`** -- Always succeeds (local source)

This connector serves as the reference implementation for the Connector behaviour and enables the data source sync pipeline to process wiki content alongside external data sources.

## Exporting Reports to Wiki

Reports can be exported as wiki pages via `DataSources.export_report_to_wiki/3`. The export:

1. Renders the report as markdown (without comments)
2. Creates a new wiki document with the report's title and rendered content
3. Optionally places the document under a specified parent page

This bridges the Agent Studio output (reports) with the knowledge management system (wiki).
