# LLM Providers and Models

Liteskill supports a wide range of LLM providers through the ReqLLM library, letting you connect to virtually any major AI model service. Providers and models are configured through the admin UI and made available to users via instance-wide flags or ACL-based sharing.

## Supported Providers

Liteskill supports 56+ providers via the ReqLLM library. The `provider_type` field on each provider record maps directly to a ReqLLM adapter. The following are among the most commonly used:

| Provider Type | Description |
|---|---|
| `amazon_bedrock` | AWS Bedrock (Claude, Llama, Cohere, etc.) |
| `anthropic` | Anthropic API (Claude models) |
| `openai` | OpenAI API (GPT-4, GPT-3.5, etc.) |
| `azure` | Azure OpenAI Service |
| `google_vertex` | Google Vertex AI (Gemini models) |
| `groq` | Groq inference (fast Llama, Mixtral) |
| `cerebras` | Cerebras inference |
| `x_ai` | xAI (Grok models) |
| `deepseek` | DeepSeek models |
| `vllm` | Self-hosted vLLM instances |
| `openrouter` | OpenRouter (multi-provider gateway) |
| `ollama` | Local Ollama instances |
| `together_ai` | Together AI |
| `fireworks_ai` | Fireworks AI |
| `mistral` | Mistral AI |
| `cohere` | Cohere API |
| `perplexity` | Perplexity AI |

The full list of valid provider types is dynamically pulled from the ReqLLM library at compile time.

## Provider Configuration

Each provider record stores connection details for a single provider endpoint.

### Provider Fields

| Field | Description |
|---|---|
| `name` | Display name (e.g., "Production Bedrock", "My OpenAI Key") |
| `provider_type` | One of the supported provider types (see above) |
| `api_key` | API key or bearer token -- encrypted at rest with AES-256-GCM |
| `provider_config` | JSON object with provider-specific settings -- encrypted at rest |
| `instance_wide` | If `true`, available to all users on the instance |
| `status` | `active` or `inactive` |

### Common Provider Config Examples

**AWS Bedrock:**

```json
{
  "region": "us-east-1"
}
```

**Azure OpenAI:**

```json
{
  "resource_name": "my-openai-resource",
  "deployment_id": "gpt-4-deployment",
  "api_version": "2024-02-15-preview"
}
```

**Custom Endpoint (vLLM, LiteLLM proxy, etc.):**

```json
{
  "base_url": "https://my-vllm-instance.example.com/v1"
}
```

**Google Vertex AI:**

```json
{
  "project_id": "my-gcp-project",
  "location": "us-central1"
}
```

### The `base_url` Field

The `base_url` key in `provider_config` is treated specially. Unlike other config keys which are passed as provider-specific options, `base_url` is extracted and passed as a top-level ReqLLM option. This allows you to point any provider adapter at a custom endpoint, which is useful for:

- **LiteLLM proxies** that expose an OpenAI-compatible API in front of many backends
- **Local vLLM instances** for self-hosted inference
- **Custom API gateways** that add logging, rate limiting, or routing

## Model Configuration

Each model record references a provider and represents a specific model available through that provider's endpoint.

### Model Fields

| Field | Description |
|---|---|
| `name` | Display name (e.g., "Claude Sonnet 4", "GPT-4o") |
| `model_id` | The provider's model identifier (e.g., `us.anthropic.claude-sonnet-4-20250514-v1:0`, `gpt-4o`) |
| `model_type` | One of `inference`, `embedding`, or `rerank` |
| `model_config` | Additional model-specific configuration -- encrypted at rest |
| `instance_wide` | If `true`, available to all users on the instance |
| `status` | `active` or `inactive` |
| `input_cost_per_million` | Cost per million input tokens (for usage tracking) |
| `output_cost_per_million` | Cost per million output tokens (for usage tracking) |
| `provider_id` | References the provider that hosts this model |

### Model Types

- **inference** -- Standard chat/completion models used for conversations and agent runs
- **embedding** -- Models that produce vector embeddings (used in RAG pipelines)
- **rerank** -- Models that re-rank search results by relevance (used in RAG search)

## Instance-Wide vs User-Scoped

Both providers and models have an `instance_wide` boolean flag:

- **Instance-wide (`true`)**: Available to all users on the Liteskill instance. Typically set by admins for shared organizational resources.
- **User-scoped (`false`)**: Only available to the creating user, unless explicitly shared via ACLs.

Visibility is determined by the following access rules (in order):

1. The user created the provider/model (`user_id` matches)
2. The provider/model is marked `instance_wide`
3. The user has been granted access via an entity ACL

Only active models with active providers appear in `list_active_models/2`, which is what the chat UI uses to populate the model selector.

## Credential Security

All sensitive fields are encrypted at rest using AES-256-GCM via the `Liteskill.Crypto.EncryptedField` and `Liteskill.Crypto.EncryptedMap` Ecto types:

- `api_key` on both providers and MCP servers
- `provider_config` on providers (may contain secrets like service account keys)
- `model_config` on models
- `headers` on MCP servers

Encryption keys are derived from the application's secret key base. Values are encrypted before database writes and decrypted transparently on reads.

## Environment Bootstrap

For AWS Bedrock deployments, Liteskill can automatically create an instance-wide provider from environment configuration on application boot. If the `bedrock_bearer_token` key is set in the application config:

1. On startup, `LlmProviders.ensure_env_providers/0` runs
2. It finds or creates a provider named "Bedrock (environment)" owned by the admin user
3. The provider is set to `instance_wide: true` with the configured region
4. The operation is idempotent -- safe to run on every boot

This allows deployment configurations to provide Bedrock credentials without requiring manual admin setup.

## Admin UI Workflow

Administrators configure providers and models through the Settings pages:

1. Navigate to **Settings > Providers** to add a new provider
   - Select the provider type
   - Enter a name, API key, and any provider-specific configuration
   - Choose whether to make it instance-wide

2. Navigate to **Settings > Models** to configure models
   - Select the provider the model belongs to
   - Enter the model name and model ID (the identifier used by the provider's API)
   - Set the model type (inference, embedding, or rerank)
   - Optionally configure input/output costs for usage tracking
   - Choose whether to make it instance-wide

3. Models appear in the conversation model selector once both the provider and model have `status: "active"`
