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
      <div class="mx-auto max-w-form space-y-6">
        <.section_card
          :if={@invitations != []}
          id="invitations"
          title="You've been invited"
          help="Join a household, or set up your own below."
        >
          <.row_list id="invitation-list">
            <.list_row :for={invitation <- @invitations} id={"invitation-#{invitation.id}"}>
              {invitation.household.name}
              <:meta :if={invitation.invited_by}>from {invitation.invited_by.email}</:meta>
              <:actions>
                <button
                  type="button"
                  class="btn btn-ghost"
                  phx-click="decline"
                  phx-value-id={invitation.id}
                >
                  Decline
                </button>
                <button
                  type="button"
                  class="btn btn-primary"
                  phx-click="join"
                  phx-value-id={invitation.id}
                >
                  Join
                </button>
              </:actions>
            </.list_row>
          </.row_list>
        </.section_card>

        <.page_header>
          Set up your household
          <:meta>Recipes, meals and plans are shared with everyone in your household.</:meta>
        </.page_header>

        <.form
          for={@form}
          id="household-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-5 rounded-box border border-base-300 bg-base-100 p-4 sm:p-5"
        >
          <.input
            field={@form[:name]}
            label="Household name"
            placeholder="The Davies household"
            autocomplete="off"
            phx-mounted={JS.focus()}
          />
          <.stepper_field
            field={@form[:usually_feeding]}
            label="Usually feeding"
            unit="people"
            event="adjust_feeding"
            max={50}
            help="How many people a planned meal is for, unless you change it."
          />

          <div>
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
            <p id="time-zone-note" class="text-sm text-base-content/70">
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
          </div>

          <div class="space-y-1">
            <.input
              type="textarea"
              id="invites"
              name="invites"
              value={@invites}
              label="Invite people (optional)"
              placeholder="partner@example.com, teen@example.com"
              errors={@invite_errors}
              rows="3"
            />
            <p class="text-sm text-base-content/70">
              Separate addresses with commas or new lines. You can also invite people later.
            </p>
          </div>

          <.button variant="primary" phx-disable-with="Creating…" class="w-full">
            Create household
          </.button>
        </.form>

        <div id="what-next" class="space-y-1 text-sm text-base-content/70">
          <p>
            Next, add a few recipes, group them into meals and plan your week. The shopping list fills itself in from the plan.
          </p>
          <p id="default-slots-note">
            {slot_names()} meal slots are added for you; the owner can change them later.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.household do
      {:ok, redirect(socket, to: ~p"/plan")}
    else
      mount_without_household(socket, Households.list_invitations_for_user(scope))
    end
  end

  # A single invitation is accepted on arrival: being invited means you're
  # expected in that household. With several, the user chooses.
  defp mount_without_household(socket, [invitation]) do
    case Households.accept_invitation(socket.assigns.current_scope, invitation.id) do
      {:ok, household} -> {:ok, joined(socket, household)}
      {:error, _reason} -> mount_without_household(socket, [])
    end
  end

  defp mount_without_household(socket, invitations) do
    form = new_household() |> Households.change_household() |> to_form()

    {:ok,
     assign(socket,
       page_title: "Welcome",
       form: form,
       invitations: invitations,
       invites: "",
       invite_errors: []
     )}
  end

  defp joined(socket, household) do
    socket
    |> put_flash(:info, "You've joined #{household.name}.")
    |> redirect(to: ~p"/plan")
  end

  @impl true
  def handle_event("validate", %{"household" => params} = all_params, socket) do
    form =
      new_household()
      |> Households.change_household(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form, invites: Map.get(all_params, "invites", ""))}
  end

  def handle_event("adjust_feeding", %{"delta" => delta}, socket) do
    form = socket.assigns.form
    feeding = step_field(form[:usually_feeding], delta, 1, 50)

    form =
      new_household()
      |> Households.change_household(Map.put(form.params, "usually_feeding", feeding))
      |> Map.put(:action, form.source.action)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"household" => params} = all_params, socket) do
    params = Map.update(params, "time_zone", @fallback_time_zone, &blank_to_fallback/1)
    invites = Map.get(all_params, "invites", "")

    case parse_invites(invites) do
      {:ok, emails} ->
        create(socket, params, emails)

      {:error, invalid} ->
        {:noreply,
         assign(socket,
           invites: invites,
           invite_errors: ["not valid email addresses: #{Enum.join(invalid, ", ")}"]
         )}
    end
  end

  def handle_event("join", %{"id" => id}, socket) do
    case Households.accept_invitation(socket.assigns.current_scope, id) do
      {:ok, household} ->
        {:noreply, joined(socket, household)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "That invitation is no longer valid.")
         |> assign(
           invitations: Households.list_invitations_for_user(socket.assigns.current_scope)
         )}
    end
  end

  def handle_event("decline", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    _ = Households.decline_invitation(scope, id)
    {:noreply, assign(socket, invitations: Households.list_invitations_for_user(scope))}
  end

  defp create(socket, params, emails) do
    scope = socket.assigns.current_scope

    case Households.create_household(scope, params) do
      {:ok, household} ->
        sent = send_invites(%{scope | household: household}, emails)

        {:noreply,
         socket
         |> put_flash(:info, "Welcome to #{household.name}.#{sent_message(sent)}")
         |> redirect(to: ~p"/plan")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :already_in_household} ->
        {:noreply, redirect(socket, to: ~p"/plan")}
    end
  end

  defp send_invites(scope, emails) do
    Enum.count(emails, fn email ->
      match?(
        {:ok, _},
        Households.invite(
          scope,
          %{email: email},
          &url(~p"/users/log-in/#{&1}"),
          url(~p"/users/log-in")
        )
      )
    end)
  end

  defp sent_message(0), do: ""
  defp sent_message(1), do: " Invitation sent."
  defp sent_message(count), do: " #{count} invitations sent."

  defp parse_invites(text) do
    emails =
      text
      |> String.split(~r/[\s,;]+/, trim: true)
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    case Enum.reject(emails, &Households.change_invitation(%{email: &1}).valid?) do
      [] -> {:ok, emails}
      invalid -> {:error, invalid}
    end
  end

  defp new_household, do: %Household{usually_feeding: 4}

  defp blank_to_fallback(value) when value in [nil, ""], do: @fallback_time_zone
  defp blank_to_fallback(value), do: value

  defp slot_names do
    MealSlot.defaults()
    |> Enum.map(fn {_key, name} -> name end)
    |> then(fn names -> Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names) end)
  end
end
