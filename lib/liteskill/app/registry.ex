defmodule Liteskill.App.Registry do
  @moduledoc """
  ETS-backed registry for platform apps.

  Stores app metadata in a named ETS table with read concurrency
  for fast lookups from plugs and permission checks.
  """

  use GenServer

  @table :liteskill_app_registry

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register an app module in the registry."
  @spec register(module()) :: :ok
  def register(app_module) do
    entry = %{
      module: app_module,
      id: app_module.id(),
      name: app_module.name(),
      description: app_module.description(),
      version: app_module.version(),
      router: app_module.router(),
      permissions: app_module.permissions(),
      default_permissions: app_module.default_permissions()
    }

    :ets.insert(@table, {app_module.id(), entry})
    :ok
  end

  @doc "Return all registered app entries."
  @spec all() :: [map()]
  def all do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, entry} -> entry end)
  end

  @doc "Look up an app by its string ID."
  @spec lookup(String.t()) :: {:ok, map()} | {:error, :not_found}
  def lookup(app_id) do
    case :ets.lookup(@table, app_id) do
      [{^app_id, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @doc "Flat list of all permissions declared by registered apps."
  @spec all_permissions() :: [String.t()]
  def all_permissions do
    all() |> Enum.flat_map(& &1.permissions)
  end

  @doc "Flat list of all default permissions declared by registered apps."
  @spec all_default_permissions() :: [String.t()]
  def all_default_permissions do
    all() |> Enum.flat_map(& &1.default_permissions)
  end

  @doc "List of `{app_id, router_module}` for apps that declare a router."
  @spec all_routers() :: [{String.t(), module()}]
  def all_routers do
    all()
    |> Enum.filter(& &1.router)
    |> Enum.map(&{&1.id, &1.router})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end
end
