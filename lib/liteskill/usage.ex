defmodule Liteskill.Usage do
  @moduledoc """
  Context for recording and querying LLM token usage.

  Usage records are stored in a dedicated projection table, independent
  of the event store, for efficient aggregation queries by user,
  conversation, model, and time period.
  """

  import Ecto.Query

  alias Liteskill.Repo
  alias Liteskill.Usage.UsageRecord

  @doc """
  Records a single LLM API call's usage.

  Required attrs: `:user_id`, `:model_id`, `:call_type`.
  """
  def record_usage(attrs) when is_map(attrs) do
    %UsageRecord{}
    |> UsageRecord.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns aggregated usage for a conversation.

  Returns a map with summed token counts and costs.
  """
  def usage_by_conversation(conversation_id) do
    UsageRecord
    |> where([r], r.conversation_id == ^conversation_id)
    |> select([r], %{
      input_tokens: coalesce(sum(r.input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      reasoning_tokens: coalesce(sum(r.reasoning_tokens), 0),
      cached_tokens: coalesce(sum(r.cached_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> Repo.one()
  end

  @doc """
  Returns aggregated usage for a user.

  ## Options

    * `:from` - Start datetime (inclusive)
    * `:to` - End datetime (exclusive)
  """
  def usage_by_user(user_id, opts \\ []) do
    UsageRecord
    |> where([r], r.user_id == ^user_id)
    |> apply_time_filters(opts)
    |> select([r], %{
      input_tokens: coalesce(sum(r.input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      reasoning_tokens: coalesce(sum(r.reasoning_tokens), 0),
      cached_tokens: coalesce(sum(r.cached_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> Repo.one()
  end

  @doc """
  Returns usage for a user grouped by model.

  ## Options

    * `:from` - Start datetime (inclusive)
    * `:to` - End datetime (exclusive)
  """
  def usage_by_user_and_model(user_id, opts \\ []) do
    UsageRecord
    |> where([r], r.user_id == ^user_id)
    |> apply_time_filters(opts)
    |> group_by([r], r.model_id)
    |> select([r], %{
      model_id: r.model_id,
      input_tokens: coalesce(sum(r.input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> order_by([r], desc: coalesce(sum(r.total_tokens), 0))
    |> Repo.all()
  end

  @doc """
  Flexible usage query builder.

  ## Options

    * `:user_id` - Filter by user
    * `:conversation_id` - Filter by conversation
    * `:model_id` - Filter by model ID string
    * `:from` - Start datetime (inclusive)
    * `:to` - End datetime (exclusive)
    * `:group_by` - `:model_id`, `:user_id`, or `:conversation_id`
  """
  def usage_summary(opts \\ []) do
    query =
      UsageRecord
      |> apply_filters(opts)
      |> apply_time_filters(opts)

    case opts[:group_by] do
      :model_id ->
        query
        |> group_by([r], r.model_id)
        |> select([r], %{
          model_id: r.model_id,
          input_tokens: coalesce(sum(r.input_tokens), 0),
          output_tokens: coalesce(sum(r.output_tokens), 0),
          total_tokens: coalesce(sum(r.total_tokens), 0),
          input_cost: sum(r.input_cost),
          output_cost: sum(r.output_cost),
          total_cost: sum(r.total_cost),
          call_count: count(r.id)
        })
        |> Repo.all()

      :user_id ->
        query
        |> group_by([r], r.user_id)
        |> select([r], %{
          user_id: r.user_id,
          input_tokens: coalesce(sum(r.input_tokens), 0),
          output_tokens: coalesce(sum(r.output_tokens), 0),
          total_tokens: coalesce(sum(r.total_tokens), 0),
          input_cost: sum(r.input_cost),
          output_cost: sum(r.output_cost),
          total_cost: sum(r.total_cost),
          call_count: count(r.id)
        })
        |> Repo.all()

      :conversation_id ->
        query
        |> group_by([r], r.conversation_id)
        |> select([r], %{
          conversation_id: r.conversation_id,
          input_tokens: coalesce(sum(r.input_tokens), 0),
          output_tokens: coalesce(sum(r.output_tokens), 0),
          total_tokens: coalesce(sum(r.total_tokens), 0),
          input_cost: sum(r.input_cost),
          output_cost: sum(r.output_cost),
          total_cost: sum(r.total_cost),
          call_count: count(r.id)
        })
        |> Repo.all()

      nil ->
        query
        |> select([r], %{
          input_tokens: coalesce(sum(r.input_tokens), 0),
          output_tokens: coalesce(sum(r.output_tokens), 0),
          total_tokens: coalesce(sum(r.total_tokens), 0),
          input_cost: sum(r.input_cost),
          output_cost: sum(r.output_cost),
          total_cost: sum(r.total_cost),
          call_count: count(r.id)
        })
        |> Repo.one()
    end
  end

  @doc """
  Returns aggregated usage for all members of a group.

  ## Options

    * `:from` - Start datetime (inclusive)
    * `:to` - End datetime (exclusive)
  """
  def usage_by_group(group_id, opts \\ []) do
    member_ids =
      from(gm in Liteskill.Groups.GroupMembership,
        where: gm.group_id == ^group_id,
        select: gm.user_id
      )
      |> Repo.all()

    UsageRecord
    |> where([r], r.user_id in ^member_ids)
    |> apply_time_filters(opts)
    |> select([r], %{
      input_tokens: coalesce(sum(r.input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      reasoning_tokens: coalesce(sum(r.reasoning_tokens), 0),
      cached_tokens: coalesce(sum(r.cached_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> Repo.one()
  end

  @doc """
  Returns aggregated usage for a run.
  """
  def usage_by_run(run_id) do
    UsageRecord
    |> where([r], r.run_id == ^run_id)
    |> select([r], %{
      input_tokens: coalesce(sum(r.input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      reasoning_tokens: coalesce(sum(r.reasoning_tokens), 0),
      cached_tokens: coalesce(sum(r.cached_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> Repo.one()
  end

  @doc """
  Returns usage for a run grouped by model.
  """
  def usage_by_run_and_model(run_id) do
    UsageRecord
    |> where([r], r.run_id == ^run_id)
    |> group_by([r], r.model_id)
    |> select([r], %{
      model_id: r.model_id,
      input_tokens: coalesce(sum(r.input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> order_by([r], desc: coalesce(sum(r.total_tokens), 0))
    |> Repo.all()
  end

  @doc """
  Returns instance-wide usage totals.

  ## Options

    * `:from` - Start datetime (inclusive)
    * `:to` - End datetime (exclusive)
  """
  def instance_totals(opts \\ []) do
    UsageRecord
    |> apply_time_filters(opts)
    |> select([r], %{
      input_tokens: coalesce(sum(r.input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      reasoning_tokens: coalesce(sum(r.reasoning_tokens), 0),
      cached_tokens: coalesce(sum(r.cached_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> Repo.one()
  end

  @doc """
  Returns daily usage totals for the given time range.

  ## Options

    * `:from` - Start datetime (inclusive)
    * `:to` - End datetime (exclusive)
  """
  def daily_totals(opts \\ []) do
    UsageRecord
    |> apply_filters(opts)
    |> apply_time_filters(opts)
    |> group_by([r], fragment("date_trunc('day', ?)", r.inserted_at))
    |> select([r], %{
      date: fragment("date_trunc('day', ?)", r.inserted_at),
      total_tokens: coalesce(sum(r.total_tokens), 0),
      input_cost: sum(r.input_cost),
      output_cost: sum(r.output_cost),
      total_cost: sum(r.total_cost),
      call_count: count(r.id)
    })
    |> order_by([r], asc: fragment("date_trunc('day', ?)", r.inserted_at))
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    query
    |> maybe_filter(:user_id, opts[:user_id])
    |> maybe_filter(:conversation_id, opts[:conversation_id])
    |> maybe_filter(:model_id, opts[:model_id])
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :user_id, val), do: where(query, [r], r.user_id == ^val)

  defp maybe_filter(query, :conversation_id, val),
    do: where(query, [r], r.conversation_id == ^val)

  defp maybe_filter(query, :model_id, val), do: where(query, [r], r.model_id == ^val)

  defp apply_time_filters(query, opts) do
    query
    |> maybe_from(opts[:from])
    |> maybe_to(opts[:to])
  end

  defp maybe_from(query, nil), do: query
  defp maybe_from(query, from), do: where(query, [r], r.inserted_at >= ^from)

  defp maybe_to(query, nil), do: query
  defp maybe_to(query, to), do: where(query, [r], r.inserted_at < ^to)
end
