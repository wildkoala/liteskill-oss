defmodule Liteskill.App do
  @moduledoc """
  Behaviour for liteskill platform apps.

  Apps are independent Mix projects that implement this behaviour to declare
  their needs (events, permissions, routes, processes) and get wired into
  the platform at startup.

  ## Usage

      defmodule MyApp do
        use Liteskill.App

        @impl true
        def id, do: "my_app"
        def name, do: "My App"
        def description, do: "Does things"
        def version, do: "0.1.0"
      end

  Optional callbacks have sensible defaults provided by the `__using__` macro.
  """

  @callback id() :: String.t()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback version() :: String.t()
  @callback child_specs() :: [Supervisor.child_spec()]
  @callback router() :: module() | nil
  @callback subscriptions() :: [String.t()]
  @callback event_types() :: [map()]
  @callback permissions() :: [String.t()]
  @callback default_permissions() :: [String.t()]
  @callback oban_queues() :: keyword()
  @callback on_start() :: :ok
  @callback migrations_path() :: String.t() | nil

  @optional_callbacks [oban_queues: 0, on_start: 0, migrations_path: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour Liteskill.App

      @impl true
      def child_specs, do: []

      @impl true
      def router, do: nil

      @impl true
      def subscriptions, do: []

      @impl true
      def event_types, do: []

      @impl true
      def permissions, do: []

      @impl true
      def default_permissions, do: []

      def oban_queues, do: []

      def on_start, do: :ok

      def migrations_path, do: nil

      defoverridable child_specs: 0,
                     router: 0,
                     subscriptions: 0,
                     event_types: 0,
                     permissions: 0,
                     default_permissions: 0,
                     oban_queues: 0,
                     on_start: 0,
                     migrations_path: 0
    end
  end
end
