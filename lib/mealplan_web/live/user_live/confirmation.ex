defmodule MealplanWeb.UserLive.Confirmation do
  @moduledoc false
  use MealplanWeb, :live_view

  alias Mealplan.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.auth_card title={if(@user.confirmed_at, do: "Log in", else: "Welcome to Mealplan")}>
        <div>
          <p class="text-sm text-base-content/70">
            {if(@user.confirmed_at, do: "Logging in as", else: "Your account is")}
          </p>
          <p id="login-email" class="break-all font-medium">{@user.email}</p>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          class="space-y-2"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="Confirming…"
            variant="primary"
            class="w-full"
          >
            Confirm and stay logged in
          </.button>
          <.button phx-disable-with="Confirming…" class="w-full">
            Confirm and log in only this time
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          class="space-y-2"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <.button phx-disable-with="Logging in…" variant="primary" class="w-full">
              Log in
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Logging in…"
              variant="primary"
              class="w-full"
            >
              Keep me logged in on this device
            </.button>
            <.button phx-disable-with="Logging in…" class="w-full">
              Log me in only this time
            </.button>
          <% end %>
        </.form>

        <:footer :if={!@user.confirmed_at}>
          Prefer a password? You can set one in your account settings once you're in.
        </:footer>
      </.auth_card>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
