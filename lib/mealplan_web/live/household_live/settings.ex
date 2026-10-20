defmodule MealplanWeb.HouseholdLive.Settings do
  @moduledoc """
  The household page: the owner edits the household's details; members see
  them read-only. Members, invitations and meal slots are added here by later
  tasks.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Households

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
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(page_title: "Household", owner?: Households.owner?(scope))
     |> assign(members: Households.list_members(scope))
     |> assign_form(Households.change_household(scope.household))}
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

  # The scope's household is refreshed by the :require_household hook; keep
  # the form in step when the owner saved from another tab or device.
  @impl true
  def handle_info({:household_updated, household}, socket) do
    {:noreply, assign_form(socket, Households.change_household(household))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset))
end
