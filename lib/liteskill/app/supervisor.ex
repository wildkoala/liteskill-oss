defmodule Liteskill.App.Supervisor do
  @moduledoc """
  Boots and supervises platform apps.

  On init, reads `Application.get_env(:liteskill, :apps, [])` and for each
  app module: starts its child_specs under an isolated supervisor subtree,
  registers it with the Registry, validates subscriptions, and calls on_start.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, _pid} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: Liteskill.App.DynamicSupervisor
      )

    apps = Application.get_env(:liteskill, :apps, [])

    for app_module <- apps do
      boot_app(app_module)
    end

    # Refresh system roles to pick up new app permissions
    if apps != [] do
      try do
        Liteskill.Rbac.ensure_system_roles()
      rescue
        e -> Logger.warning("Failed to refresh system roles after app boot: #{inspect(e)}")
      end
    end

    {:ok, %{apps: apps}}
  end

  defp boot_app(app_module) do
    app_id = app_module.id()
    child_specs = app_module.child_specs()

    # Start app's processes under an isolated supervisor subtree
    if child_specs != [] do
      app_supervisor_spec = %{
        id: :"app_#{app_id}",
        start:
          {Supervisor, :start_link,
           [child_specs, [strategy: :one_for_one, name: :"Liteskill.App.#{app_id}"]]}
      }

      case DynamicSupervisor.start_child(Liteskill.App.DynamicSupervisor, app_supervisor_spec) do
        {:ok, _pid} -> :ok
        {:error, reason} -> Logger.error("Failed to start app #{app_id}: #{inspect(reason)}")
      end
    end

    # Register in ETS
    Liteskill.App.Registry.register(app_module)

    # Validate subscriptions
    Liteskill.App.EventBridge.wire_subscriptions(app_module)

    # Run app boot hook
    if function_exported?(app_module, :on_start, 0) do
      try do
        app_module.on_start()
      rescue
        e -> Logger.warning("App #{app_id} on_start failed: #{inspect(e)}")
      end
    end

    Logger.info("App started: #{app_id} (#{app_module.name()})")
  end
end
