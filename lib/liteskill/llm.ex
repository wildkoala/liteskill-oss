defmodule Liteskill.LLM do
  @moduledoc """
  Public API for LLM interactions.

  Uses ReqLLM for transport. `complete/2` is used for non-streaming calls
  (e.g. conversation title generation). Streaming is handled by
  `StreamHandler` directly.

  Models are configured in the database via admin UI — there are no
  hardcoded model IDs or env-var fallbacks for model selection.
  """

  alias Liteskill.LLM.StreamHandler
  alias Liteskill.Usage

  @doc """
  Sends a non-streaming completion request.

  Requires either `:llm_model` (a `%LlmModel{}` struct) or `:model_id` +
  `:provider_options` to be passed in opts.

  ## Options
    - `:llm_model` - A `%LlmModel{}` struct with full provider config
    - `:model_id` - Model ID string (requires `:provider_options` too)
    - `:max_tokens` - Maximum tokens to generate
    - `:temperature` - Sampling temperature
    - `:system` - System prompt
    - `:generate_fn` - Override the generation function (for testing)
  """
  def complete(messages, opts \\ []) do
    llm_model = Keyword.get(opts, :llm_model)

    {model, req_opts} =
      if llm_model do
        {model_spec, model_opts} = Liteskill.LlmModels.build_provider_options(llm_model)
        {model_spec, model_opts}
      else
        model_id =
          Keyword.get(opts, :model_id) ||
            raise "No model specified: pass :llm_model or :model_id option"

        provider_opts = Keyword.get(opts, :provider_options, [])
        {StreamHandler.to_req_llm_model(model_id), [provider_options: provider_opts]}
      end

    context = StreamHandler.to_req_llm_context(messages)

    req_opts =
      case Keyword.get(opts, :system) do
        nil -> req_opts
        system -> Keyword.put(req_opts, :system_prompt, system)
      end

    req_opts =
      case Keyword.get(opts, :temperature) do
        nil -> req_opts
        temp -> Keyword.put(req_opts, :temperature, temp)
      end

    req_opts =
      case Keyword.get(opts, :max_tokens) do
        nil -> req_opts
        max -> Keyword.put(req_opts, :max_tokens, max)
      end

    generate_fn = Keyword.get(opts, :generate_fn, &default_generate/3)

    case generate_fn.(model, context, req_opts) do
      {:ok, response} ->
        text = ReqLLM.Response.text(response) || ""
        maybe_record_complete_usage(response, model, opts)

        {:ok,
         %{"output" => %{"message" => %{"role" => "assistant", "content" => [%{"text" => text}]}}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # coveralls-ignore-start
  defp default_generate(model, context, opts) do
    ReqLLM.generate_text(model, context, opts)
  end

  # coveralls-ignore-stop

  defp maybe_record_complete_usage(response, model, opts) do
    user_id = Keyword.get(opts, :user_id)

    if user_id do
      usage = ReqLLM.Response.usage(response) || %{}
      model_id = if is_map(model), do: model[:id], else: to_string(model)

      llm_model = Keyword.get(opts, :llm_model)

      llm_model_id =
        case llm_model do
          %{id: id} -> id
          _ -> nil
        end

      input_tokens = usage[:input_tokens] || 0
      output_tokens = usage[:output_tokens] || 0

      {input_cost, output_cost, total_cost} =
        resolve_costs(usage, llm_model, input_tokens, output_tokens)

      attrs = %{
        user_id: user_id,
        conversation_id: Keyword.get(opts, :conversation_id),
        model_id: model_id || "unknown",
        llm_model_id: llm_model_id,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: usage[:total_tokens] || 0,
        reasoning_tokens: usage[:reasoning_tokens] || 0,
        cached_tokens: usage[:cached_tokens] || 0,
        cache_creation_tokens: usage[:cache_creation_tokens] || 0,
        input_cost: input_cost,
        output_cost: output_cost,
        reasoning_cost: to_decimal(usage[:reasoning_cost]),
        total_cost: total_cost,
        call_type: "complete"
      }

      Usage.record_usage(attrs)
    end
  end

  defp to_decimal(nil), do: nil
  # coveralls-ignore-next-line
  defp to_decimal(%Decimal{} = d), do: d
  # coveralls-ignore-next-line
  defp to_decimal(val) when is_float(val), do: Decimal.from_float(val)
  # coveralls-ignore-next-line
  defp to_decimal(val) when is_integer(val), do: Decimal.new(val)

  defp resolve_costs(usage, llm_model, input_tokens, output_tokens) do
    api_input = to_decimal(usage[:input_cost])
    api_output = to_decimal(usage[:output_cost])
    api_total = to_decimal(usage[:total_cost])

    if api_total do
      # coveralls-ignore-next-line
      {api_input, api_output, api_total}
    else
      input_cost = cost_from_rate(input_tokens, llm_model && llm_model.input_cost_per_million)
      output_cost = cost_from_rate(output_tokens, llm_model && llm_model.output_cost_per_million)

      total_cost =
        if input_cost || output_cost do
          Decimal.add(input_cost || Decimal.new(0), output_cost || Decimal.new(0))
        end

      {input_cost, output_cost, total_cost}
    end
  end

  defp cost_from_rate(_tokens, nil), do: nil
  # coveralls-ignore-next-line
  defp cost_from_rate(0, _rate), do: Decimal.new(0)

  defp cost_from_rate(tokens, rate) do
    tokens |> Decimal.new() |> Decimal.mult(rate) |> Decimal.div(1_000_000)
  end

  @doc """
  Returns active LLM models available to the given user (DB-only).
  """
  def available_models(user_id) do
    Liteskill.LlmModels.list_active_models(user_id, model_type: "inference")
  end
end
