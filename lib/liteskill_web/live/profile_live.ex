defmodule LiteskillWeb.ProfileLive do
  @moduledoc """
  Profile components and event handlers, rendered within ChatLive's main area.
  Handles user-facing settings: account info and password change.
  """

  use LiteskillWeb, :html

  alias Liteskill.Accounts
  alias Liteskill.Accounts.User

  @profile_actions [:info, :password]

  def profile_action?(action), do: action in @profile_actions

  def profile_assigns do
    [
      password_form: to_form(%{"current" => "", "new" => "", "confirm" => ""}, as: :password),
      password_error: nil,
      password_success: false
    ]
  end

  def apply_profile_action(socket, action, _user) do
    load_tab_data(socket, action)
  end

  defp load_tab_data(socket, :password) do
    Phoenix.Component.assign(socket,
      page_title: "Change Password",
      password_error: nil,
      password_success: false
    )
  end

  defp load_tab_data(socket, _action) do
    Phoenix.Component.assign(socket, page_title: "Profile")
  end

  # --- Public component ---

  attr :live_action, :atom, required: true
  attr :current_user, :map, required: true
  attr :sidebar_open, :boolean, required: true
  attr :password_form, :any, required: true
  attr :password_error, :string
  attr :password_success, :boolean

  def profile(assigns) do
    ~H"""
    <header class="px-4 py-3 border-b border-base-300 flex-shrink-0">
      <div class="flex items-center gap-2">
        <button
          :if={!@sidebar_open}
          phx-click="toggle_sidebar"
          class="btn btn-circle btn-ghost btn-sm"
        >
          <.icon name="hero-bars-3-micro" class="size-5" />
        </button>
        <h1 class="text-lg font-semibold">Profile</h1>
      </div>
    </header>

    <div class="border-b border-base-300 px-4 flex-shrink-0">
      <div class="flex gap-1 overflow-x-auto" role="tablist">
        <.tab_link label="Info" to={~p"/profile"} active={@live_action == :info} />
        <.tab_link label="Password" to={~p"/profile/password"} active={@live_action == :password} />
      </div>
    </div>

    <div class="flex-1 overflow-y-auto p-6">
      <div class="mx-auto max-w-3xl">
        {render_tab(assigns)}
      </div>
    </div>
    """
  end

  defp tab_link(assigns) do
    ~H"""
    <.link
      navigate={@to}
      class={[
        "tab tab-bordered whitespace-nowrap",
        @active && "tab-active"
      ]}
    >
      {@label}
    </.link>
    """
  end

  # --- Info Tab ---

  defp render_tab(%{live_action: :info} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title mb-4">Account Information</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.info_row label="Name" value={@current_user.name || "—"} />
            <.info_row label="Email" value={@current_user.email} />
            <.info_row label="Sign-on Source" value={sign_on_source(@current_user)} />
            <div>
              <div class="text-sm text-base-content/60 mb-1">Role</div>
              <span class={[
                "badge",
                User.admin?(@current_user) && "badge-primary",
                !User.admin?(@current_user) && "badge-neutral"
              ]}>
                {String.capitalize(@current_user.role)}
              </span>
            </div>
            <.info_row
              label="Member Since"
              value={Calendar.strftime(@current_user.inserted_at, "%B %d, %Y")}
            />
          </div>
        </div>
      </div>

      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title mb-4">Accent Color</h2>
          <div class="flex flex-wrap gap-3">
            <%= for color <- User.accent_colors() do %>
              <button
                phx-click="set_accent_color"
                phx-value-color={color}
                class={[
                  "w-10 h-10 rounded-full border-2 border-base-300 transition-all",
                  accent_swatch_bg(color),
                  User.accent_color(@current_user) == color &&
                    "ring-2 ring-offset-2 ring-offset-base-100 ring-base-content scale-110"
                ]}
                title={color_label(color)}
              />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Password Tab ---

  defp render_tab(%{live_action: :password} = assigns) do
    ~H"""
    <div :if={@current_user.force_password_change} class="alert alert-warning mb-4">
      <.icon name="hero-exclamation-triangle-mini" class="size-5" />
      <span>You must change your password before continuing.</span>
    </div>
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <h2 class="card-title mb-4">Change Password</h2>
        <.form for={@password_form} phx-submit="change_password" class="space-y-4 max-w-sm">
          <div class="form-control">
            <label class="label"><span class="label-text">Current Password</span></label>
            <input
              type="password"
              name="password[current]"
              class="input input-bordered w-full"
              required
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">New Password</span></label>
            <input
              type="password"
              name="password[new]"
              class="input input-bordered w-full"
              required
              minlength="12"
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Confirm New Password</span></label>
            <input
              type="password"
              name="password[confirm]"
              class="input input-bordered w-full"
              required
              minlength="12"
            />
          </div>
          <p :if={@password_error} class="text-error text-sm">{@password_error}</p>
          <p :if={@password_success} class="text-success text-sm">Password changed successfully.</p>
          <button type="submit" class="btn btn-primary">Update Password</button>
        </.form>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp info_row(assigns) do
    ~H"""
    <div>
      <div class="text-sm text-base-content/60 mb-1">{@label}</div>
      <div class="font-medium">{@value}</div>
    </div>
    """
  end

  defp sign_on_source(%User{oidc_sub: nil}), do: "Local (password)"
  defp sign_on_source(%User{oidc_issuer: issuer}), do: "SSO (#{issuer})"

  defp accent_swatch_bg("pink"), do: "bg-pink-500"
  defp accent_swatch_bg("red"), do: "bg-red-500"
  defp accent_swatch_bg("orange"), do: "bg-orange-500"
  defp accent_swatch_bg("yellow"), do: "bg-yellow-400"
  defp accent_swatch_bg("green"), do: "bg-green-500"
  defp accent_swatch_bg("cyan"), do: "bg-cyan-500"
  defp accent_swatch_bg("blue"), do: "bg-blue-500"
  defp accent_swatch_bg("royal-blue"), do: "bg-blue-700"
  defp accent_swatch_bg("purple"), do: "bg-violet-500"
  defp accent_swatch_bg("brown"), do: "bg-amber-800"
  defp accent_swatch_bg("black"), do: "bg-neutral-900"

  defp color_label(color), do: color |> String.replace("-", " ") |> String.capitalize()

  # --- Event Handlers (called from ChatLive) ---

  def handle_event("change_password", %{"password" => params}, socket) do
    current = params["current"]
    new_pass = params["new"]
    confirm = params["confirm"]

    cond do
      new_pass != confirm ->
        {:noreply,
         Phoenix.Component.assign(socket,
           password_error: "Passwords do not match",
           password_success: false
         )}

      String.length(new_pass) < 12 ->
        {:noreply,
         Phoenix.Component.assign(socket,
           password_error: "New password must be at least 12 characters",
           password_success: false
         )}

      true ->
        case Accounts.change_password(socket.assigns.current_user, current, new_pass) do
          {:ok, user} ->
            {:noreply,
             socket
             |> Phoenix.Component.assign(
               current_user: user,
               password_error: nil,
               password_success: true,
               password_form:
                 to_form(%{"current" => "", "new" => "", "confirm" => ""}, as: :password)
             )}

          {:error, :invalid_current_password} ->
            {:noreply,
             Phoenix.Component.assign(socket,
               password_error: "Current password is incorrect",
               password_success: false
             )}

          {:error, _changeset} ->
            {:noreply,
             Phoenix.Component.assign(socket,
               password_error: "Failed to change password",
               password_success: false
             )}
        end
    end
  end

  def handle_event("set_accent_color", %{"color" => color}, socket) do
    user = socket.assigns.current_user

    case Accounts.update_preferences(user, %{"accent_color" => color}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(current_user: updated_user)
         |> Phoenix.LiveView.push_event("set-accent", %{color: color})}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
