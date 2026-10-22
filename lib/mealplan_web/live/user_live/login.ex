defmodule MealplanWeb.UserLive.Login do
  @moduledoc false
  use MealplanWeb, :live_view

  alias Mealplan.Accounts
  alias MealplanWeb.LoginThrottle
  alias MealplanWeb.TrustedProxy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.auth_card title={if(@current_scope, do: "Log in again", else: "Log in")}>
        <:intro :if={!@current_scope}>Plan the week's meals and shop for them together.</:intro>

        <p class="text-sm text-base-content/70">
          <%= cond do %>
            <% @current_scope -> %>
              You need to reauthenticate to change your email or password.
            <% @password? -> %>
              Mealplan is invite-only. Use the email address your invitation was sent to.
            <% true -> %>
              Mealplan is invite-only. Use the email address your invitation was sent to, and we'll email you a link.
          <% end %>
        </p>

        <div
          :if={local_mail_adapter?()}
          id="local-mail-note"
          class="rounded-box bg-info/10 p-3 text-sm"
        >
          You are running the local mail adapter. To see sent emails, visit <.link
            href="/dev/mailbox"
            class="underline"
          >the mailbox page</.link>.
        </div>

        <.form
          for={@form}
          id={if(@password?, do: "login_form_password", else: "login_form_magic")}
          action={~p"/users/log-in"}
          phx-change="change"
          phx-submit={if(@password?, do: "submit_password", else: "submit_magic")}
          phx-trigger-action={@password? and @trigger_submit}
          class="space-y-4"
        >
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            placeholder="you@example.com"
            required
            phx-mounted={!@password? && JS.focus()}
          />
          <%= if @password? do %>
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              spellcheck="false"
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:remember_me]}
              type="checkbox"
              label="Stay logged in on this device"
            />
            <.button variant="primary" class="w-full" phx-disable-with="Logging in…">
              Log in
            </.button>
          <% else %>
            <.button variant="primary" class="w-full" phx-disable-with="Sending…">
              Email me a login link
            </.button>
          <% end %>
        </.form>

        <button
          type="button"
          id="toggle-password"
          class="btn btn-ghost w-full"
          phx-click="toggle_password"
        >
          {if(@password?, do: "Email me a link instead", else: "Use a password instead")}
        </button>

        <:footer :if={!@current_scope}>
          No invitation? Ask someone in your household to invite you from their Household page.
        </:footer>
      </.auth_card>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email, "remember_me" => "true"}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       password?: false,
       trigger_submit: false,
       client_ip: if(connected?(socket), do: TrustedProxy.client_ip_from_socket(socket))
     )}
  end

  # Keeps the email (and the remember-me box) when switching between the
  # link and the password; the password itself never goes back to the page.
  @impl true
  def handle_event("change", %{"user" => params}, socket) do
    params = socket.assigns.form.params |> Map.merge(params) |> Map.delete("password")
    {:noreply, assign(socket, form: to_form(params, as: "user"))}
  end

  def handle_event("toggle_password", _params, socket),
    do: {:noreply, update(socket, :password?, &(!&1))}

  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case LoginThrottle.magic_link(socket.assigns.client_ip, email) do
      :ok ->
        # Fire and forget: the response is the same whether or not the email exists.
        _ =
          if user = Accounts.get_user_by_email(email) do
            Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
          end

        info =
          "If your email is in our system, you will receive instructions for logging in shortly."

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, LoginThrottle.message())}
    end
  end

  defp local_mail_adapter? do
    Application.get_env(:mealplan, Mealplan.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
