# First Run

This guide walks you through the initial setup after launching Liteskill for the first time.

## Overview

When Liteskill boots, it automatically creates a built-in admin account (`admin@liteskill.local`) with no password set. The first time you log in as this admin, a setup wizard walks you through essential configuration. After the wizard, you configure LLM providers and models through the admin settings UI to start chatting.

## Step 1: Register or Log In

Visit [http://localhost:4000](http://localhost:4000) (or wherever you deployed Liteskill).

You have two options:

- **Register a new account** at `/register` -- The first user to register is automatically granted the admin role. This is the simplest path for getting started.
- **Use the built-in admin account** -- Navigate to `/login` and sign in with `admin@liteskill.local`. Since this account has no password initially, you will be redirected to the setup wizard at `/setup`.

> **Note:** If OIDC (SSO) is configured via environment variables, a "Sign in with SSO" option also appears on the login page.

## Step 2: Setup Wizard

The setup wizard appears when the admin account requires initial configuration (specifically, when `admin@liteskill.local` has no password set). It guides you through three steps:

### Step 2a: Set Admin Password

The first screen asks you to set a password for the admin account:

- Minimum length: **12 characters**
- You must confirm the password by entering it twice
- Click **"Set Password & Continue"** to proceed

This password protects the built-in admin account. If you registered a separate account in Step 1, you already set a password during registration -- but completing this step ensures the built-in admin account is also secured.

### Step 2b: Select Data Sources

The second screen displays available data source integrations (for example, Google Drive, web URLs, wikis, and other connectors). Data sources power the RAG pipeline by providing documents for embedding and retrieval.

- Click on any source type to toggle it on or off
- Selected sources are highlighted with a green border
- Click **"Continue"** to proceed with your selections, or **"Skip for now"** to configure data sources later

You can always add, remove, or reconfigure data sources after setup at **Sources** in the main navigation.

### Step 2c: Configure Selected Sources

If you selected any data sources in the previous step, you are prompted to enter connection details for each one (API keys, URLs, credentials, etc.):

- A progress indicator shows which source you are configuring (e.g., "1 of 3")
- Fill in the required fields and click **"Save & Continue"**
- Click **"Skip"** to skip a particular source and configure it later

After the last source is configured (or skipped), you are redirected to the login page.

## Step 3: Add an LLM Provider

Before you can chat, you need to configure at least one LLM provider. Providers represent your connections to LLM services (OpenAI, Anthropic, AWS Bedrock, Google, etc.).

1. Log in and navigate to the **Admin** section (accessible from the sidebar or at `/admin`)
2. Go to **Admin > Providers** (or navigate directly to `/admin/providers`)
3. Click **"New Provider"** and fill in:
   - **Name** -- A descriptive name (e.g., "OpenAI Production", "Anthropic", "Local vLLM")
   - **Provider Type** -- Select from 56+ supported providers. Common choices include `openai`, `anthropic`, `aws_bedrock`, `google`, `groq`, `azure_openai`, `deepseek`, and `openrouter`
   - **API Key** -- Your provider's API key (encrypted at rest with AES-256-GCM)
   - **Provider Config** (optional) -- Provider-specific configuration as JSON. Examples:

     | Provider | Config Example |
     |----------|---------------|
     | AWS Bedrock | `{"region": "us-east-1"}` |
     | Azure OpenAI | `{"resource_name": "myres", "deployment_id": "gpt4", "api_version": "2024-02-01"}` |
     | Custom endpoint / LiteLLM | `{"base_url": "http://litellm:4000/v1"}` |
     | Google Vertex AI | `{"project_id": "my-project", "location": "us-central1"}` |

   - **Instance Wide** -- Toggle on to make this provider available to all users. Leave off to restrict it to yourself.

4. Click **"Save"** to create the provider

## Step 4: Add a Model

Models represent specific LLM models available through a provider. You need at least one model to start chatting.

1. Go to **Admin > Models** (or navigate directly to `/admin/models`)
2. Click **"New Model"** and fill in:
   - **Name** -- A display name (e.g., "GPT-4o", "Claude Sonnet 4", "Llama 3.1 70B")
   - **Model ID** -- The model identifier your provider expects (e.g., `gpt-4o`, `claude-sonnet-4-20250514`, `meta.llama3-1-70b-instruct-v1:0`)
   - **Model Type** -- Select the model's purpose:
     - `inference` -- Standard chat/completion model (default)
     - `embedding` -- Embedding model for RAG
     - `rerank` -- Reranking model for RAG search results
   - **Provider** -- Select the provider you created in Step 3
   - **Instance Wide** -- Toggle on to make this model available to all users
   - **Input Cost per Million** (optional) -- Cost per million input tokens, for usage tracking
   - **Output Cost per Million** (optional) -- Cost per million output tokens, for usage tracking

3. Click **"Save"** to create the model

## Step 5: Start Chatting

With a provider and model configured:

1. Navigate to the home page (`/`) or click **"New Conversation"** in the sidebar
2. Select the model you want to use from the model dropdown
3. Type a message and press Enter or click Send
4. The model's response streams in real-time, token by token

## What Next?

After your initial setup, you may want to explore:

- **[MCP Tools](/mcp)** -- Connect external tool servers so the AI can call APIs and execute actions
- **[Sources](/sources)** -- Set up data sources for RAG to ground model responses in your own documents
- **[Reports](/reports)** -- Create structured documents with nested sections and comments
- **[Agent Studio](/agents)** -- Define AI agents with different strategies and assemble multi-agent teams
- **[Admin > Users](/admin/users)** -- Manage user accounts and roles
- **[Admin > Groups](/admin/groups)** -- Create groups for ACL-based sharing

## Troubleshooting

**Setup wizard does not appear**

The setup wizard only appears for the `admin@liteskill.local` account when it has no password set. If you registered a separate account first, that account becomes admin automatically and the setup wizard is not needed. You can configure providers and models directly from the admin UI.

**"No models available" when starting a conversation**

Make sure you have created at least one provider and one model with the **Instance Wide** flag enabled (or assigned to your user). Check **Admin > Providers** and **Admin > Models** to verify their status is "active".

**Model returns errors**

Verify that:

- The API key on the provider is correct
- The model ID matches what the provider expects
- Any required provider config (region, deployment ID, etc.) is set correctly
- The provider service is reachable from the server

Check the server logs for detailed error messages. In development, logs appear in the terminal where you ran `mix phx.server`. With Docker, use `docker compose logs -f app`.
