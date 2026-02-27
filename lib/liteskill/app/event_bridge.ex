defmodule Liteskill.App.EventBridge do
  @moduledoc """
  Thin helpers around Phoenix.PubSub for app-level events.

  Provides subscribe/publish functions and validates subscription topics at boot.
  Actual subscribing is done by each app's own GenServer processes per OTP rules.
  """

  require Logger

  @pubsub Liteskill.PubSub

  @doc "Subscribe the calling process to a PubSub topic."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end

  @doc """
  Publish an event on app-level PubSub topics.

  Broadcasts on both `"app:<app_id>"` and `"app:<app_id>:<event_type>"`.
  """
  @spec publish(String.t(), String.t(), map()) :: :ok
  def publish(app_id, event_type, payload) do
    message = %{app_id: app_id, event_type: event_type, payload: payload}

    Phoenix.PubSub.broadcast(@pubsub, "app:#{app_id}", {:app_event, message})
    Phoenix.PubSub.broadcast(@pubsub, "app:#{app_id}:#{event_type}", {:app_event, message})

    :ok
  end

  @doc """
  Validate subscription topics declared by an app module at boot time.

  Logs warnings for any topics that don't follow the expected naming conventions.
  """
  @spec wire_subscriptions(module()) :: :ok
  def wire_subscriptions(app_module) do
    app_id = app_module.id()

    for topic <- app_module.subscriptions() do
      unless valid_topic?(topic, app_id) do
        Logger.warning(
          "App #{app_id} declares subscription to unexpected topic: #{topic}"
        )
      end
    end

    :ok
  end

  defp valid_topic?(topic, _app_id) do
    String.starts_with?(topic, "app:") or
      String.starts_with?(topic, "events:") or
      String.starts_with?(topic, "event_store:")
  end
end
