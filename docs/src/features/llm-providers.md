# LLM Providers

Liteskill supports multiple LLM providers through a pluggable provider system powered by ReqLLM.

## Provider Types

Providers are configured in the database via the admin UI. Supported provider types include:

- **Amazon Bedrock** — AWS-hosted models (Claude, Llama, etc.)
- **OpenRouter** — Multi-model gateway with OAuth PKCE support
- **OpenAI-compatible** — Any endpoint that speaks the OpenAI API format

## Provider Configuration

Each provider record stores:

- **Name** — Display name
- **Provider type** — Determines the API protocol
- **API key** — Encrypted at rest via `Liteskill.Crypto`
- **Provider config** — Type-specific settings (e.g. AWS region)
- **Instance-wide flag** — If true, available to all users
- **Status** — Active or inactive

## Access Control

- **Instance-wide providers** are available to all users
- **User-owned providers** are private to their creator
- **Admin-granted access** — Admins can grant `viewer` role on a provider to specific users via ACLs

## Models

Models are defined under providers. Each model specifies:

- Model ID (the provider's model identifier)
- Display name
- Model type (`inference`, `embedding`, `rerank`)
- Cost rates (input/output per million tokens)
- Active/inactive status

Users select models when creating conversations or configuring agents.
