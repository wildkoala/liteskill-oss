# RAG Context

`Liteskill.Rag` manages the RAG pipeline: collections, sources, documents, chunks, embeddings, and search.

## Boundary

```elixir
use Boundary,
  top_level?: true,
  deps: [Liteskill.Authorization, Liteskill.DataSources, Liteskill.LlmModels, Liteskill.LlmProviders, Liteskill.Settings],
  exports: [Collection, Source, Document, Chunk, Chunker, CohereClient, DocumentSyncWorker, EmbedQueue, EmbeddingClient, EmbeddingRequest, IngestWorker, OpenAIEmbeddingClient, Pipeline, ReembedWorker, WikiSyncWorker]
```

## Data Model

- **Collection** — Top-level grouping, per user
- **Source** — A source within a collection (e.g. "wiki", "manual")
- **Document** — Content with title, status, metadata, and content hash
- **Chunk** — Text chunk with position, token count, and pgvector embedding

## Collection & Source CRUD

Standard CRUD with user ownership checks. Collections and sources are scoped to the creating user.

## Embedding

`embed_chunks(document_id, chunks, user_id, opts)`:
1. Validates ownership chain (document → source → collection)
2. Sends texts to `EmbedQueue` for embedding
3. Inserts chunk rows with pgvector embeddings in a transaction
4. Updates document status to `"embedded"`

## Search

| Function | Description |
|----------|-------------|
| `search(collection_id, query, user_id, opts)` | Vector search within a collection |
| `rerank(query, chunks, opts)` | Rerank results via Cohere |
| `search_and_rerank(collection_id, query, user_id, opts)` | Combined search + rerank |
| `search_accessible(collection_id, query, user_id, opts)` | ACL-aware search for shared collections |
| `augment_context(query, user_id, opts)` | Cross-collection search for conversation context |

## Wiki Integration

- `find_or_create_wiki_collection(user_id)` — Gets or creates the "Wiki" collection
- `find_or_create_wiki_source(collection_id, user_id)` — Gets or creates the "wiki" source
- `find_rag_document_by_wiki_id(wiki_document_id, user_id)` — Finds RAG doc by wiki doc ID

## URL Ingestion

`ingest_url(collection_id, url, user_id, opts)` enqueues an `IngestWorker` Oban job that fetches, chunks, and embeds content from a URL.
