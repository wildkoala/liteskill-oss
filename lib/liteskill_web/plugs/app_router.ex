defmodule LiteskillWeb.Plugs.AppRouter do
  @moduledoc """
  Plug that intercepts `/apps/:app_id/*` requests and delegates
  to the matching app's router.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: [app_id | rest]} = conn, _opts) do
    case Liteskill.App.Registry.lookup(app_id) do
      {:ok, %{router: router}} when not is_nil(router) ->
        conn
        |> Plug.Conn.put_private(:liteskill_app_id, app_id)
        |> Map.put(:path_info, rest)
        |> Map.put(:script_name, conn.script_name ++ ["apps", app_id])
        |> router.call(router.init([]))

      {:ok, _no_router} ->
        conn
        |> Plug.Conn.put_status(404)
        |> Phoenix.Controller.json(%{error: "app has no router"})
        |> Plug.Conn.halt()

      {:error, :not_found} ->
        conn
        |> Plug.Conn.put_status(404)
        |> Phoenix.Controller.json(%{error: "app not found"})
        |> Plug.Conn.halt()
    end
  end

  def call(conn, _opts) do
    conn
    |> Plug.Conn.put_status(404)
    |> Phoenix.Controller.json(%{error: "not found"})
    |> Plug.Conn.halt()
  end
end
