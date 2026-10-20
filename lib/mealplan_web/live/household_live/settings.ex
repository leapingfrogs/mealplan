defmodule MealplanWeb.HouseholdLive.Settings do
  @moduledoc """
  The household page: the owner edits the household's details; members see
  them read-only. Members, invitations and meal slots are added here by later
  tasks.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Households
  alias Mealplan.Households.Invitation

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@current_scope.household.name}
        <:subtitle>
          <%= if @owner? do %>
            You're the owner.
          <% else %>
            Only the owner can change these details.
          <% end %>
        </:subtitle>
      </.header>

      <.form
        :if={@owner?}
        for={@form}
        id="household-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-2"
      >
        <.input field={@form[:name]} label="Household name" autocomplete="off" />
        <.input
          field={@form[:usually_feeding]}
          type="number"
          label="Usually feeding"
          min="1"
          max="50"
          inputmode="numeric"
        />
        <p class="text-sm text-base-content/60 -mt-1 mb-2">
          How many people a newly planned meal is for.
        </p>
        <.input
          field={@form[:time_zone]}
          label="Time zone"
          autocomplete="off"
          spellcheck="false"
          placeholder="Europe/London"
        />
        <button
          type="button"
          id="use-device-time-zone"
          class="btn btn-sm btn-ghost -mt-1"
          phx-hook=".DeviceTimeZone"
          data-target="household_time_zone"
        >
          Use this device's time zone
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".DeviceTimeZone">
          export default {
            mounted() {
              this.el.addEventListener("click", () => {
                const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
                const input = document.getElementById(this.el.dataset.target)
                if (zone && input) {
                  input.value = zone
                  input.dispatchEvent(new Event("input", {bubbles: true}))
                }
              })
            }
          }
        </script>
        <div>
          <.button variant="primary" phx-disable-with="Saving..." class="mt-4">Save</.button>
        </div>
      </.form>

      <dl :if={!@owner?} id="household-details" class="divide-y divide-base-300">
        <div class="flex justify-between py-3">
          <dt class="text-base-content/60">Usually feeding</dt>
          <dd id="usually-feeding">{@current_scope.household.usually_feeding}</dd>
        </div>
        <div class="flex justify-between py-3">
          <dt class="text-base-content/60">Time zone</dt>
          <dd id="time-zone">{@current_scope.household.time_zone}</dd>
        </div>
      </dl>

      <section class="space-y-3 pt-4">
        <h2 class="text-lg font-semibold">Members</h2>
        <ul id="members" class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={member <- @members}
            id={"member-#{member.id}"}
            class="flex justify-between gap-3 px-4 py-3"
          >
            <span class="truncate">
              {member.email}<span
                :if={member.id == @current_scope.user.id}
                class="text-base-content/60"
              > (you)</span>
            </span>
            <span :if={member.id == @current_scope.household.owner_id} class="badge badge-ghost">
              owner
            </span>
          </li>
        </ul>
      </section>

      <section :if={@owner?} class="space-y-3 pt-4">
        <h2 class="text-lg font-semibold">Invite someone</h2>
        <.form
          for={@invite_form}
          id="invite-form"
          phx-change="validate_invite"
          phx-submit="invite"
          class="flex flex-wrap items-start gap-2"
        >
          <div class="flex-1 min-w-48">
            <.input
              field={@invite_form[:email]}
              type="email"
              placeholder="name@example.com"
              autocomplete="off"
              spellcheck="false"
            />
          </div>
          <.button variant="primary" phx-disable-with="Sending...">Invite</.button>
        </.form>
        <p class="text-sm text-base-content/60">
          They'll get an email with a link to log in and join. Invitations expire after {Invitation.validity_days()} days.
        </p>

        <ul
          :if={@pending_invitations != []}
          id="pending-invitations"
          class="divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={invitation <- @pending_invitations}
            id={"invitation-#{invitation.id}"}
            class="flex items-center justify-between gap-3 px-4 py-3"
          >
            <span class="min-w-0">
              <span class="block truncate">{invitation.email}</span>
              <span class="text-sm text-base-content/60">
                invited · {expires_in(invitation.expires_at)}
              </span>
            </span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="revoke"
              phx-value-id={invitation.id}
              data-confirm={"Revoke the invitation for #{invitation.email}?"}
            >
              Revoke
            </button>
          </li>
        </ul>
      </section>

      <section :if={@my_invitations != []} id="my-invitations" class="space-y-3 pt-4">
        <h2 class="text-lg font-semibold">Invitations for you</h2>
        <p class="text-sm text-base-content/60">
          To join another household, you'll need to leave this one first.
        </p>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={invitation <- @my_invitations}
            id={"my-invitation-#{invitation.id}"}
            class="flex items-center justify-between gap-3 px-4 py-3"
          >
            <span class="min-w-0 truncate">{invitation.household.name}</span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="decline"
              phx-value-id={invitation.id}
            >
              Decline
            </button>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(page_title: "Household", owner?: Households.owner?(scope))
     |> assign(invite_form: to_form(Households.change_invitation()))
     |> assign_lists()
     |> assign_form(Households.change_household(scope.household))}
  end

  defp assign_lists(socket) do
    scope = socket.assigns.current_scope

    pending =
      if socket.assigns.owner?, do: Households.list_pending_invitations(scope), else: []

    assign(socket,
      members: Households.list_members(scope),
      pending_invitations: pending,
      my_invitations: Households.list_invitations_for_user(scope)
    )
  end

  @impl true
  def handle_event("validate", %{"household" => params}, socket) do
    changeset =
      socket.assigns.current_scope.household
      |> Households.change_household(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"household" => params}, socket) do
    case Households.update_household(socket.assigns.current_scope, params) do
      {:ok, household} ->
        {:noreply,
         socket
         |> put_flash(:info, "Household updated.")
         |> assign_form(Households.change_household(household))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the owner can change the household.")}
    end
  end

  def handle_event("validate_invite", %{"invitation" => params}, socket) do
    form = params |> Households.change_invitation() |> Map.put(:action, :validate) |> to_form()
    {:noreply, assign(socket, invite_form: form)}
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    scope = socket.assigns.current_scope

    case Households.invite(scope, params, &url(~p"/users/log-in/#{&1}"), url(~p"/users/log-in")) do
      {:ok, invitation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{invitation.email}.")
         |> assign(invite_form: to_form(Households.change_invitation()))
         |> assign_lists()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, invite_form: to_form(changeset))}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Too many invitations. Please try again later.")}

      {:error, :delivery_failed} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "The invitation was saved but the email couldn't be sent. Try again shortly."
         )
         |> assign_lists()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the owner can invite people.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case Households.revoke_invitation(socket.assigns.current_scope, id) do
      {:ok, invitation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation for #{invitation.email} revoked.")
         |> assign_lists()}

      {:error, _reason} ->
        {:noreply,
         socket |> put_flash(:error, "That invitation is no longer pending.") |> assign_lists()}
    end
  end

  def handle_event("decline", %{"id" => id}, socket) do
    _ = Households.decline_invitation(socket.assigns.current_scope, id)
    {:noreply, socket |> put_flash(:info, "Invitation declined.") |> assign_lists()}
  end

  # The scope's household is refreshed by the :require_household hook; keep
  # the form in step when the owner saved from another tab or device.
  @impl true
  def handle_info({:household_updated, household}, socket) do
    {:noreply, assign_form(socket, Households.change_household(household))}
  end

  # Someone joined, or invitations changed (possibly from another device).
  def handle_info({:household_changed, _what}, socket), do: {:noreply, assign_lists(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset))

  defp expires_in(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :day) do
      0 -> "expires today"
      1 -> "expires tomorrow"
      days -> "expires in #{days} days"
    end
  end
end
