defmodule Liteskill.Rag.EmbeddingClient do
  @moduledoc """
  Facade for embedding API calls. Delegates to `ReqLLM.embed/3` using the
  configured embedding model's provider for authentication.

  Falls back to Bedrock Cohere embed-v4 when no model is configured.
  """

  alias Liteskill.Rag.RequestLogger
  alias Liteskill.{LlmModels, LlmProviders, Settings}

  require Logger

  @default_embed_model "us.cohere.embed-v4:0"

  @default_base_urls %{
    "openrouter" => "https://openrouter.ai/api/v1",
    "openai" => "https://api.openai.com/v1"
  }

  @doc """
  Embed a list of texts using the currently configured embedding provider.

  ## Options

    * `:input_type` - "search_document" or "search_query" (default "search_document")
    * `:dimensions` - output dimension (default 1024)
    * `:truncate` - truncation strategy (default "RIGHT")
    * `:plug` - Req test plug (passed through as `req_http_options: [plug: ...]`)
    * `:user_id` - user ID for embedding request tracking
  """
  def embed(texts, opts) do
    {user_id, opts} = Keyword.pop(opts, :user_id)
    {plug_opt, embed_opts} = Keyword.pop(opts, :plug)

    {model_spec, req_opts, log_model_id} = build_embed_options(embed_opts)

    # Wrap plug in req_http_options for ReqLLM compatibility
    req_opts =
      if plug_opt do
        Keyword.put(req_opts, :req_http_options, plug: plug_opt)
      else
        req_opts
      end

    start = System.monotonic_time(:millisecond)
    result = ReqLLM.embed(model_spec, texts, req_opts)
    latency = System.monotonic_time(:millisecond) - start

    RequestLogger.log_request(user_id, %{
      request_type: "embed",
      model_id: log_model_id,
      input_count: length(texts),
      token_count: RequestLogger.estimate_token_count(texts),
      latency_ms: latency,
      result: result
    })

    result
  end

  defp build_embed_options(opts) do
    {input_type, opts} = Keyword.pop(opts, :input_type, "search_document")
    {dimensions, opts} = Keyword.pop(opts, :dimensions, 1024)
    {truncate, _opts} = Keyword.pop(opts, :truncate, "RIGHT")

    case resolve_provider() do
      {:bedrock, model, provider} ->
        region = get_in(provider.provider_config || %{}, ["region"]) || "us-east-1"

        # Note: :dimensions is intentionally omitted from Bedrock provider_options.
        # ReqLLM's Bedrock provider schema does not declare it (upstream gap);
        # Cohere embed-v4 defaults to 1024 dimensions which matches our default.
        req_opts = [
          provider_options: [
            region: region,
            input_type: input_type,
            truncate: truncate
          ]
        ]

        req_opts =
          if provider.api_key,
            do: Keyword.put(req_opts, :api_key, provider.api_key),
            # coveralls-ignore-next-line
            else: req_opts

        {"amazon_bedrock:#{model.model_id}", req_opts, model.model_id}

      {:openai_compat, model, provider} ->
        req_opts = [
          base_url: resolve_base_url(provider),
          provider_options: [dimensions: dimensions]
        ]

        req_opts =
          if provider.api_key,
            do: Keyword.put(req_opts, :api_key, provider.api_key),
            # coveralls-ignore-next-line
            else: req_opts

        {to_openai_spec(model.model_id), req_opts, model.model_id}

      :no_model ->
        creds = resolve_bedrock_credentials()

        # Note: :dimensions omitted — same upstream gap as {:bedrock, ...} above.
        req_opts = [
          provider_options: [
            region: creds.region,
            input_type: input_type,
            truncate: truncate
          ]
        ]

        req_opts =
          if creds.token, do: Keyword.put(req_opts, :api_key, creds.token), else: req_opts

        {"amazon_bedrock:#{@default_embed_model}", req_opts, @default_embed_model}
    end
  end

  # Map OpenAI-compatible model IDs to LLMDB-recognized OpenAI model specs.
  # Strips provider prefixes (e.g. "openai/text-embedding-3-small" → "text-embedding-3-small").
  defp to_openai_spec(model_id) do
    canonical = model_id |> String.split("/") |> List.last()
    "openai:#{canonical}"
  end

  defp resolve_provider do
    settings = Settings.get()

    if is_nil(settings.embedding_model_id) do
      :no_model
    else
      model = LlmModels.get_model!(settings.embedding_model_id)
      provider = model.provider

      if provider.provider_type == "amazon_bedrock" do
        {:bedrock, model, provider}
      else
        {:openai_compat, model, provider}
      end
    end
  end

  defp resolve_base_url(provider) do
    config_url = get_in(provider.provider_config || %{}, ["base_url"])
    config_url || Map.get(@default_base_urls, provider.provider_type, "https://api.openai.com/v1")
  end

  defp resolve_bedrock_credentials do
    db_creds =
      try do
        LlmProviders.get_bedrock_credentials()
      rescue
        # coveralls-ignore-start
        e ->
          Logger.warning("Failed to resolve DB credentials: #{Exception.message(e)}")
          nil
          # coveralls-ignore-stop
      end

    case db_creds do
      # coveralls-ignore-start — tested via CohereClient.rerank DB credentials test
      %{api_key: token, region: region} ->
        %{token: token, region: region}

      # coveralls-ignore-stop
      nil ->
        config = Application.get_env(:liteskill, Liteskill.LLM, [])

        %{
          token: Keyword.get(config, :bedrock_bearer_token),
          region: Keyword.get(config, :bedrock_region, "us-east-1")
        }
    end
  end
end
