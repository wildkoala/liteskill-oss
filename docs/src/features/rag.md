# RAG (Retrieval-Augmented Generation)

Liteskill includes a full RAG pipeline: document ingestion, chunking, embedding generation, semantic search, and reranking.

## Pipeline

1. **Ingest** — Documents are added to a collection via URL, manual upload, or data source sync
2. **Chunk** — Documents are split into chunks
3. **Embed** — Chunks are embedded using a configured embedding model (Cohere or OpenAI-compatible)
4. **Search** — User queries are embedded and matched against chunks using pgvector cosine similarity
5. **Rerank** — Search results are optionally reranked using a Cohere rerank model

## Data Model

- **Collection** — Top-level grouping (e.g. "Wiki", "Engineering Docs")
- **Source** — A source within a collection (e.g. "wiki", "manual")
- **Document** — A single document with content and metadata
- **Chunk** — A text chunk with its pgvector embedding

## Embedding

Embeddings are generated via `Liteskill.Rag.EmbedQueue`, which batches requests and manages throughput. Two client implementations:

- `CohereClient` — For Cohere's embed and rerank APIs
- `OpenAIEmbeddingClient` — For OpenAI-compatible embedding endpoints

## Context Augmentation

During conversations, RAG context is injected automatically:

1. The user's message is embedded
2. All accessible collections are searched
3. Top results are reranked
4. Relevant chunks are included as context for the LLM

## Wiki Integration

Wiki pages are automatically synced to RAG collections. When a wiki page is created or updated, a background job (`WikiSyncWorker`) updates the corresponding RAG document and re-embeds its chunks.

## Re-embedding

Admins can trigger a full re-embedding of all documents (e.g. after changing the embedding model) via the `ReembedWorker`.
