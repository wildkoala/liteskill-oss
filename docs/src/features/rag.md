# RAG (Retrieval-Augmented Generation)

Liteskill includes a full RAG pipeline that lets you ground AI conversations in your own data. By ingesting documents into a vector store, the system can retrieve relevant context at query time and include it in the LLM prompt, producing more accurate and source-backed responses.

## What is RAG?

Retrieval-Augmented Generation (RAG) enhances LLM responses by retrieving relevant information from a knowledge base before generating an answer. Instead of relying solely on the model's training data, RAG:

1. Converts your documents into vector embeddings
2. At query time, finds the most semantically similar document chunks
3. Includes those chunks as context in the LLM prompt
4. The LLM generates its response informed by your specific data

This approach reduces hallucination, provides up-to-date information, and enables citations back to source material.

## Data Model

RAG data is organized in a four-level hierarchy:

### Collections

Collections are the top-level containers for related documents. Each collection has a configurable embedding dimension that determines the vector size used for all chunks within it.

| Field | Description |
|---|---|
| `name` | Display name for the collection |
| `description` | Optional description |
| `embedding_dimensions` | Vector dimension size. Valid values: 256, 384, 512, 768, **1024** (default), 1536 |

The embedding dimension is set at collection creation and applies to all chunks within the collection. Choose a dimension that balances search quality against storage and compute costs.

### Sources

Sources categorize documents by their origin within a collection.

| Field | Description |
|---|---|
| `name` | Source name (e.g., domain name for web sources, "wiki" for wiki content) |
| `source_type` | One of `manual`, `upload`, `web`, or `api` |
| `metadata` | Additional source-specific metadata |

When ingesting URLs, the system automatically creates sources named after the URL's domain (e.g., `docs.example.com`).

### Documents

Documents represent individual pieces of content within a source.

| Field | Description |
|---|---|
| `title` | Document title |
| `content` | Full text content |
| `metadata` | Arbitrary metadata (URL, content type, wiki document ID, etc.) |
| `status` | `pending`, `embedded`, or `error` |
| `chunk_count` | Number of chunks generated from this document |
| `content_hash` | SHA-256 hash for deduplication |

### Chunks

Chunks are the atomic units of the vector store. Each chunk contains a text segment and its vector embedding.

| Field | Description |
|---|---|
| `content` | Text content of the chunk |
| `position` | Order within the document (0-indexed) |
| `token_count` | Estimated token count (bytes / 4) |
| `embedding` | pgvector vector (dimension matches the collection) |
| `content_hash` | SHA-256 hash for deduplication |

## Chunking

Liteskill uses a recursive text splitter that breaks documents into chunks suitable for embedding. The algorithm uses a hierarchy of separators, trying each level before falling back to the next:

1. **Paragraphs** (`\n\n`) -- Split on double newlines
2. **Lines** (`\n`) -- Split on single newlines
3. **Sentences** (`. `) -- Split on sentence boundaries
4. **Words** (` `) -- Split on spaces
5. **Force-split** -- If no separator works, split at the character limit

After splitting, small pieces are merged back together up to the target chunk size, with configurable overlap to maintain context across chunk boundaries.

### Default Parameters

| Parameter | Default | Description |
|---|---|---|
| `chunk_size` | 2000 | Target chunk size in characters |
| `overlap` | 200 | Overlap between adjacent chunks in characters |

These defaults can be overridden per-ingestion when calling `Rag.ingest_url/4`.

## Embedding

Liteskill uses **Cohere embed-v4** on AWS Bedrock for generating vector embeddings. The embedding client:

- Sends text to the `us.cohere.embed-v4:0` model endpoint
- Uses `float` embedding type
- Supports configurable output dimensions (matching the collection's setting)
- Differentiates between `search_document` (for indexing) and `search_query` (for queries) input types
- Logs all embedding requests for monitoring (model, latency, token count, status)

Embeddings are stored as pgvector vectors in the `rag_chunks` table, enabling efficient similarity search using PostgreSQL's vector indexing.

## Search

RAG search uses cosine distance (`<=>` operator) for vector similarity matching. The search pipeline supports several modes:

### Basic Vector Search

`Rag.search/4` performs a straightforward vector similarity search within a single collection:

1. Embeds the query text using Cohere embed-v4 with `search_query` input type
2. Finds the nearest chunks by cosine distance
3. Returns results ordered by distance, with a configurable limit (default 20)

### Search with Reranking

`Rag.search_and_rerank/4` adds a reranking step for higher-quality results:

1. Performs a broad vector search (default 50 results)
2. Passes results through **Cohere rerank-v3.5** (`cohere.rerank-v3-5:0` on Bedrock)
3. Returns the top N results (default 5) ranked by relevance score

If reranking fails (e.g., Bedrock error), the system falls back to returning the top N vector search results without relevance scores.

### Context Augmentation

`Rag.augment_context/3` searches across all collections accessible to the user:

1. Embeds the query
2. Searches all collections the user owns or has wiki ACL access to (up to 100 results)
3. Preloads document and source metadata for each result
4. Reranks with Cohere rerank-v3.5 if enough results are found (40+ triggers reranking)
5. Returns enriched results with source attribution

This is used during chat to automatically find relevant context from the user's entire knowledge base.

## URL Ingestion

`Rag.ingest_url/4` provides a one-call pipeline to ingest web content into the RAG store. It enqueues an Oban background job (`IngestWorker`) that performs the following steps:

1. **Fetch** -- Makes an HTTP request to the URL (supports GET, POST, PUT, PATCH, DELETE methods with custom headers)
2. **Validate** -- Checks the response status (must be 2xx) and content type (must be text-based: `text/*`, `application/json`, `application/xml`, etc.). Binary content is permanently rejected with `{:cancel, :binary_content}`, preventing retries.
3. **Source creation** -- Finds or creates a source named after the URL's domain within the target collection
4. **Document creation** -- Creates a document with the URL path as its title and the response body as content
5. **Chunking** -- Splits the content using the recursive text splitter (with optional custom chunk size and overlap)
6. **Embedding** -- Generates embeddings for all chunks and stores them in the vector store

The worker runs in the `rag_ingest` Oban queue with up to 3 retry attempts. Binary content responses result in a permanent cancellation (`{:cancel, :binary_content}`) to avoid wasteful retries.

## RAG Citations in Chat

When RAG context is used during a conversation, the sources appear as citations in the assistant's messages. The `rag_sources` field on messages stores source attribution data, which the UI renders as clickable footnotes linking back to the original documents.

This allows users to verify the AI's claims by checking the source material directly.

## Pipeline Dashboard

The RAG pipeline includes monitoring through the embedding request tracking system. Each embedding and reranking call is logged with:

- Request type (embed or rerank)
- Model ID
- Input count and estimated token count
- Latency in milliseconds
- Success/failure status and error messages

This data powers the pipeline dashboard for monitoring ingestion job health and performance.
