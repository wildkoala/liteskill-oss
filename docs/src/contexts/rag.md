# RAG Context

Module: `Liteskill.Rag`

The RAG (Retrieval-Augmented Generation) context manages collections, sources, documents, chunks, embedding generation, and semantic search. It uses pgvector for vector similarity search.

## Data Model

```
Collection
  |-- Source (domain grouping)
       |-- Document (content unit)
            |-- Chunk (embedded text segment)
```

### Collection

`Liteskill.Rag.Collection` -- top-level grouping of RAG content per user.

### Source

`Liteskill.Rag.Source` -- groups documents by origin (e.g. domain name, "wiki").

### Document

`Liteskill.Rag.Document` -- a single content unit with title, content, metadata, and status.

### Chunk

`Liteskill.Rag.Chunk` -- an embedded text segment with content, position, metadata, token count, content hash, and a pgvector embedding column.

## Collection CRUD

### `create_collection(attrs, user_id)`

```elixir
create_collection(map(), binary_id)
:: {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
```

### `list_collections(user_id)`

Lists collections owned by the user.

```elixir
list_collections(binary_id) :: [Collection.t()]
```

### `list_accessible_collections(user_id)`

Lists collections the user can access: their own plus Wiki collections from users who share wiki spaces with them.

```elixir
list_accessible_collections(binary_id) :: [Collection.t()]
```

### `get_collection(id, user_id)`

```elixir
get_collection(binary_id, binary_id)
:: {:ok, Collection.t()} | {:error, :not_found}
```

### `update_collection(id, attrs, user_id)`

```elixir
update_collection(binary_id, map(), binary_id)
:: {:ok, Collection.t()} | {:error, :not_found | Ecto.Changeset.t()}
```

### `delete_collection(id, user_id)`

```elixir
delete_collection(binary_id, binary_id)
:: {:ok, Collection.t()} | {:error, :not_found}
```

## Source Management

### `create_source(collection_id, attrs, user_id)`

Creates a source within a collection.

```elixir
create_source(binary_id, map(), binary_id)
:: {:ok, Source.t()} | {:error, :not_found | Ecto.Changeset.t()}
```

### `list_sources(collection_id, user_id)`

```elixir
list_sources(binary_id, binary_id)
:: {:ok, [Source.t()]} | {:error, :not_found}
```

### `get_source(id, user_id)`, `update_source(id, attrs, user_id)`, `delete_source(id, user_id)`

Standard CRUD with ownership checks.

## Document Management

### `create_document(source_id, attrs, user_id)`

Creates a document within a source. Auto-generates a content hash if content is provided.

```elixir
create_document(binary_id, map(), binary_id)
:: {:ok, Document.t()} | {:error, :not_found | Ecto.Changeset.t()}
```

### `list_documents(source_id, user_id)`

```elixir
list_documents(binary_id, binary_id)
:: {:ok, [Document.t()]} | {:error, :not_found}
```

### `get_document(id, user_id)`, `delete_document(id, user_id)`

Standard CRUD with ownership checks.

## Chunk Operations

### `embed_chunks(document_id, chunks, user_id, opts \\ [])`

Embeds a list of chunks for a document using the CohereClient. Stores chunks with their embeddings via `Repo.insert_all` in a transaction and updates the document status to `"embedded"`.

```elixir
embed_chunks(binary_id, [%{content: String.t(), position: integer()}], binary_id, keyword())
:: {:ok, term()} | {:error, term()}
```

Options:
- `:plug` -- Req test plug for CohereClient
- `:dimensions` -- embedding dimensions (defaults to collection's `embedding_dimensions`)

### `list_chunks_for_document(rag_document_id)`

Lists all chunks for a RAG document ordered by position.

```elixir
list_chunks_for_document(binary_id) :: [Chunk.t()]
```

### `delete_document_chunks(document_id)`

Deletes all chunks for a document.

```elixir
delete_document_chunks(binary_id) :: {:ok, integer()}
```

## Search Operations

### `search(collection_id, query, user_id, opts \\ [])`

Performs vector similarity search within a collection. Embeds the query text, then searches by cosine distance (`<=>` operator).

```elixir
search(binary_id, String.t(), binary_id, keyword())
:: {:ok, [%{chunk: Chunk.t(), distance: float()}]} | {:error, term()}
```

Options:
- `:limit` -- max results (default: 20)
- `:dimensions` -- embedding dimensions
- `:plug` -- Req test plug

### `rerank(query, chunks, opts \\ [])`

Reranks search results using Cohere rerank-v3.5.

```elixir
rerank(String.t(), [%{chunk: Chunk.t()}], keyword())
:: {:ok, [%{chunk: Chunk.t(), relevance_score: float()}]} | {:error, term()}
```

Options:
- `:top_n` -- number of top results (default: 5)
- `:user_id` -- for request tracking
- `:plug` -- Req test plug

### `search_and_rerank(collection_id, query, user_id, opts \\ [])`

Combines vector search with reranking. Searches with a broader limit, then reranks to get the top results. Falls back to raw search results if reranking fails.

```elixir
search_and_rerank(binary_id, String.t(), binary_id, keyword())
:: {:ok, [%{chunk: Chunk.t(), relevance_score: float() | nil}]} | {:error, term()}
```

Options:
- `:search_limit` -- initial search limit (default: 50)
- `:top_n` -- rerank top-N (default: 5)

### `search_accessible(collection_id, query, user_id, opts \\ [])`

Searches a collection with ACL awareness. For shared wiki collections, only returns chunks from wiki spaces the user has access to.

```elixir
search_accessible(binary_id, String.t(), binary_id, keyword())
:: {:ok, [%{chunk: Chunk.t(), relevance_score: float() | nil}]} | {:error, :not_found | term()}
```

### `augment_context(query, user_id, opts \\ [])`

Searches all accessible collections for the user (owned and shared wiki) to provide RAG context for a conversation. Performs vector search across all collections, preloads document and source associations, then reranks if there are enough results.

```elixir
augment_context(String.t(), binary_id, keyword())
:: {:ok, [%{chunk: Chunk.t(), relevance_score: float() | nil}]}
```

## Ingestion

### `ingest_url(collection_id, url, user_id, opts \\ [])`

Enqueues an Oban `IngestWorker` job to ingest content from a URL.

```elixir
ingest_url(binary_id, String.t(), binary_id, keyword())
:: {:ok, Oban.Job.t()} | {:error, :not_found}
```

Options:
- `:method` -- HTTP method (default: `"GET"`)
- `:headers` -- custom HTTP headers (default: `%{}`)
- `:chunk_size` -- target chunk size in characters
- `:overlap` -- overlap between chunks in characters

## Supporting Modules

### CohereClient

`Liteskill.Rag.CohereClient` -- Req-based HTTP client for Cohere models on AWS Bedrock.

- `embed(texts, opts)` -- Embeds texts using Cohere embed-v4 (`us.cohere.embed-v4:0`). Supports `input_type` (`"search_document"` or `"search_query"`), `dimensions` (default 1024), and `truncate` (default `"RIGHT"`).
- `rerank(query, documents, opts)` -- Reranks documents using Cohere rerank-v3.5 (`cohere.rerank-v3-5:0`). Supports `top_n` (default 5) and `max_tokens_per_doc` (default 4096).

Both functions log requests to the `EmbeddingRequest` tracking table when a `user_id` is provided.

Credentials are resolved from the database (active instance-wide Bedrock provider) with fallback to application config.

### Chunker

`Liteskill.Rag.Chunker` -- recursive text splitter for document chunking.

```elixir
Chunker.split(text, opts \\ [])
:: [%{content: String.t(), position: integer(), token_count: integer()}]
```

Options:
- `:chunk_size` -- target chunk size in characters (default: 2000)
- `:overlap` -- overlap between chunks in characters (default: 200)
- `:separators` -- list of separators to try in order (default: `["\n\n", "\n", ". ", " "]`)

Splitting hierarchy: paragraph -> line -> sentence -> word -> force-split (by grapheme).

### IngestWorker

`Liteskill.Rag.IngestWorker` -- Oban worker for URL ingestion.

- Queue: `:rag_ingest`
- Max attempts: 3
- Pipeline: fetch URL -> validate text content (rejects binary content with `:cancel`) -> find/create source (by domain) -> create document -> chunk text -> embed chunks
- Supported content types: `text/*`, `application/json`, `application/xml`, `application/yaml`, `application/javascript`, and various XML-based types

### WikiSyncWorker

`Liteskill.Rag.WikiSyncWorker` -- Oban worker for syncing wiki content into RAG collections.

### EmbeddingRequest

`Liteskill.Rag.EmbeddingRequest` -- tracking schema for embed/rerank API calls. Records request type, status, latency, input count, token count, model ID, and error messages.
