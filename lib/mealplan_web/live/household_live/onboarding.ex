defmodule MealplanWeb.HouseholdLive.Onboarding do
  @moduledoc """
  First stop for users without a household: create one. Joining by invitation
  is added with household invitations.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Households.MealSlot

  # Used when the browser doesn't report a time zone; editable later.
  @fallback_time_zone "Etc/UTC"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md space-y-8">
        <.header>
          Set up your household
          <:subtitle>
            Recipes, meals and plans are shared with everyone in your household.
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="household-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-2"
        >
          <.input
            field={@form[:name]}
            label="Household name"
            placeholder="The Davies household"
            autocomplete="off"
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:usually_feeding]}
            type="number"
            label="Usually feeding"
            min="1"
            max="50"
            inputmode="numeric"
          />
          <p class="text-sm text-base-content/60 -mt-1 mb-4">
            How many people a planned meal is for, unless you change it.
          </p>

          <input
            type="hidden"
            id="household-time-zone"
            name={@form[:time_zone].name}
            value={@form[:time_zone].value}
            phx-hook=".BrowserTimeZone"
          />
          <script :type={Phoenix.LiveView.ColocatedHook} name=".BrowserTimeZone">
            export default {
              mounted() {
                const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
                if (zone && !this.el.value) {
                  this.el.value = zone
                  this.el.dispatchEvent(new Event("input", {bubbles: true}))
                }
              }
            }
          </script>
          <p id="time-zone-note" class="text-sm text-base-content/60">
            Days and weeks follow
            <span class="font-medium text-base-content">
              {@form[:time_zone].value || "your device's"}
            </span>
            time.
          </p>
          <p
            :for={msg <- Enum.map(@form[:time_zone].errors, &translate_error/1)}
            class="text-sm text-error"
          >
            Time zone {msg}
          </p>

          <.button variant="primary" phx-disable-with="Creating..." class="w-full mt-4">
            Create household
          </.button>
        </.form>

        <p id="default-slots-note" class="text-sm text-base-content/60">
          {slot_names()} meal slots are added for you; the owner can change them later.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_scope.household do
      {:ok, redirect(socket, to: ~p"/plan")}
    else
      form = %Household{usually_feeding: 4} |> Households.change_household() |> to_form()
      {:ok, assign(socket, page_title: "Welcome", form: form)}
    end
  end

  @impl true
  def handle_event("validate", %{"household" => params}, socket) do
    form =
      %Household{}
      |> Households.change_household(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"household" => params}, socket) do
    params = Map.update(params, "time_zone", @fallback_time_zone, &blank_to_fallback/1)

    case Households.create_household(socket.assigns.current_scope, params) do
      {:ok, household} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome to #{household.name}.")
         |> redirect(to: ~p"/plan")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :already_in_household} ->
        {:noreply, redirect(socket, to: ~p"/plan")}
    end
  end

  defp blank_to_fallback(value) when value in [nil, ""], do: @fallback_time_zone
  defp blank_to_fallback(value), do: value

  defp slot_names do
    MealSlot.defaults()
    |> Enum.map(fn {_key, name} -> name end)
    |> then(fn names -> Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names) end)
  end
end
