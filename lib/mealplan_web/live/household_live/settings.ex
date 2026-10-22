defmodule MealplanWeb.HouseholdLive.Settings do
  @moduledoc """
  The household page. The owner edits the details and meal slots, manages
  members and invitations, and can delete the household; members see it
  read-only and can leave.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Households
  alias Mealplan.Households.Invitation
  alias Mealplan.Households.MealSlot

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="household">
      <.page_header>
        {@current_scope.household.name}
        <:meta>{summary(@owner?, @members, @pending_invitations)}</:meta>
      </.page_header>

      <div class="space-y-4">
        <.section_card
          id="details"
          title="Details"
          help="Usually feeding sets the servings for newly planned meals."
        >
          <.form
            :if={@owner?}
            for={@form}
            id="household-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <.input field={@form[:name]} label="Household name" autocomplete="off" />
            <.stepper_field
              field={@form[:usually_feeding]}
              label="Usually feeding"
              unit="people"
              event="adjust_feeding"
              max={50}
            />
            <div>
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
                class="btn btn-ghost mt-1"
                phx-hook=".DeviceTimeZone"
                data-target="household_time_zone"
              >
                <.icon name="hero-globe-europe-africa" class="size-4" /> Use this device's time zone
              </button>
            </div>
            <div class="flex justify-end">
              <.button variant="primary" phx-disable-with="Saving…">Save details</.button>
            </div>
          </.form>
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

          <dl :if={!@owner?} id="household-details" class="divide-y divide-base-300">
            <div class="flex justify-between gap-3 py-3">
              <dt class="text-base-content/70">Usually feeding</dt>
              <dd id="usually-feeding" class="tabular-nums">
                {@current_scope.household.usually_feeding}
              </dd>
            </div>
            <div class="flex justify-between gap-3 py-3">
              <dt class="text-base-content/70">Time zone</dt>
              <dd id="time-zone">{@current_scope.household.time_zone}</dd>
            </div>
          </dl>
        </.section_card>

        <.section_card
          id="meal-slots-section"
          title="Meal slots"
          help={
            if(@owner?,
              do: "The times of day you plan meals for, in order. Drag or use ⋮ to reorder.",
              else: "The times of day you plan meals for, in order."
            )
          }
        >
          <.row_list
            id="meal-slots"
            phx-hook="Sortable"
            data-event="reorder_slots"
            data-sortable={to_string(@owner? and is_nil(@editing_slot_id))}
          >
            <%= for {slot, index} <- Enum.with_index(@meal_slots) do %>
              <li
                :if={@editing_slot_id == slot.id}
                id={"slot-#{slot.id}"}
                data-id={slot.id}
                class="px-4 py-3"
              >
                <.form
                  for={@slot_form}
                  id="rename-slot-form"
                  phx-change="validate_slot"
                  phx-submit="rename_slot"
                  class="flex flex-wrap items-start gap-2"
                >
                  <input type="hidden" name="slot_id" value={slot.id} />
                  <div class="min-w-40 flex-1">
                    <.input
                      field={@slot_form[:name]}
                      aria-label="Meal slot name"
                      autocomplete="off"
                      phx-mounted={JS.focus()}
                    />
                  </div>
                  <button type="button" class="btn btn-ghost" phx-click="cancel_rename">
                    Cancel
                  </button>
                  <.button variant="primary" phx-disable-with="Saving…">Save</.button>
                </.form>
              </li>
              <.list_row
                :if={@editing_slot_id != slot.id}
                id={"slot-#{slot.id}"}
                sortable_id={if(@owner? and is_nil(@editing_slot_id), do: slot.id)}
              >
                {slot.name}
                <:lead :if={@owner?}>
                  <.icon
                    name="hero-bars-2"
                    class="hidden size-5 cursor-grab text-base-content/40 sm:block"
                  />
                </:lead>
                <:actions :if={@owner?}>
                  <.row_menu id={"slot-#{slot.id}-menu"} label={"Actions for #{slot.name}"}>
                    <:item :if={index > 0}>
                      <button
                        type="button"
                        phx-click={close_menu("move_slot", "slot-#{slot.id}-menu")}
                        phx-value-id={slot.id}
                        phx-value-direction="up"
                      >
                        <.icon name="hero-arrow-up" class="size-4" /> Move earlier
                      </button>
                    </:item>
                    <:item :if={index < length(@meal_slots) - 1}>
                      <button
                        type="button"
                        phx-click={close_menu("move_slot", "slot-#{slot.id}-menu")}
                        phx-value-id={slot.id}
                        phx-value-direction="down"
                      >
                        <.icon name="hero-arrow-down" class="size-4" /> Move later
                      </button>
                    </:item>
                    <:item>
                      <button
                        type="button"
                        phx-click={close_menu("edit_slot", "slot-#{slot.id}-menu")}
                        phx-value-id={slot.id}
                      >
                        <.icon name="hero-pencil" class="size-4" /> Rename
                      </button>
                    </:item>
                    <:item :if={length(@meal_slots) > 1}>
                      <button
                        type="button"
                        class="text-error"
                        phx-click={close_menu("delete_slot", "slot-#{slot.id}-menu")}
                        phx-value-id={slot.id}
                        data-confirm={"Delete the #{slot.name} slot?"}
                      >
                        <.icon name="hero-trash" class="size-4" /> Delete
                      </button>
                    </:item>
                  </.row_menu>
                </:actions>
              </.list_row>
            <% end %>
          </.row_list>

          <.confirm_panel
            :if={@deleting_slot}
            id="delete-slot-panel"
            title={"Delete #{@deleting_slot.slot.name}?"}
            confirm={"Delete #{@deleting_slot.slot.name}"}
            form="delete-slot-form"
            on_cancel="cancel_delete_slot"
          >
            {ngettext(
              "It has a meal planned from today:",
              "It has %{count} meals planned from today:",
              length(@deleting_slot.upcoming)
            )}
            <span :if={@deleting_slot.archive?}>Past weeks will still show it.</span>
            <:item :for={planned <- @deleting_slot.upcoming}>
              {planned.meal.name}, {Calendar.strftime(planned.date, "%a %-d %b")}
            </:item>
            <:extra>
              <form id="delete-slot-form" phx-submit="confirm_delete_slot">
                <label for="delete-slot-upcoming" class="label mb-1 text-sm">Those meals</label>
                <select id="delete-slot-upcoming" name="upcoming" class="select w-full">
                  <option
                    :for={slot <- @meal_slots}
                    :if={slot.id != @deleting_slot.slot.id}
                    value={slot.id}
                  >
                    Move to {slot.name}
                  </option>
                  <option value="remove">Remove them from the plan</option>
                </select>
              </form>
            </:extra>
          </.confirm_panel>

          <.add_form
            :if={@owner?}
            for={@new_slot_form}
            id="new-slot-form"
            field={@new_slot_form[:name]}
            label="Add a meal slot"
            placeholder="Add a slot, e.g. Elevenses"
            phx-change="validate_new_slot"
            phx-submit="create_slot"
          />
          <button
            :if={@owner? and @missing_defaults != []}
            type="button"
            id="restore-default-slots"
            class="btn btn-ghost btn-sm"
            phx-click="restore_slots"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Restore default slots
          </button>
        </.section_card>

        <.section_card
          id="members-section"
          title="Members"
          help="Everyone here can plan, cook and shop. Only the owner manages the household."
        >
          <.row_list id="members">
            <.list_row :for={member <- @members} id={"member-#{member.id}"}>
              {member.email}
              <:meta>{member_role(member, @current_scope)}</:meta>
              <:actions :if={@owner? and member.id != @current_scope.household.owner_id}>
                <.row_menu id={"member-#{member.id}-menu"} label={"Actions for #{member.email}"}>
                  <:item>
                    <button
                      type="button"
                      phx-click={close_menu("transfer", "member-#{member.id}-menu")}
                      phx-value-id={member.id}
                      data-confirm={"Make #{member.email} the owner? You'll become a regular member."}
                    >
                      <.icon name="hero-key" class="size-4" /> Make owner
                    </button>
                  </:item>
                  <:item>
                    <button
                      type="button"
                      class="text-error"
                      phx-click={close_menu("remove", "member-#{member.id}-menu")}
                      phx-value-id={member.id}
                      data-confirm={"Remove #{member.email} from the household?"}
                    >
                      <.icon name="hero-user-minus" class="size-4" /> Remove
                    </button>
                  </:item>
                </.row_menu>
              </:actions>
            </.list_row>
          </.row_list>

          <.row_list :if={@pending_invitations != []} id="pending-invitations">
            <.list_row :for={invitation <- @pending_invitations} id={"invitation-#{invitation.id}"}>
              {invitation.email}
              <:meta>Invited · {expires_in(invitation.expires_at)}</:meta>
              <:actions>
                <button
                  type="button"
                  class="btn btn-ghost"
                  phx-click="revoke"
                  phx-value-id={invitation.id}
                  data-confirm={"Revoke the invitation for #{invitation.email}?"}
                >
                  Revoke
                </button>
              </:actions>
            </.list_row>
          </.row_list>

          <div :if={@owner?} class="space-y-1">
            <.add_form
              for={@invite_form}
              id="invite-form"
              field={@invite_form[:email]}
              type="email"
              label="Invite someone"
              show_label
              placeholder="name@example.com"
              button="Invite"
              phx-change="validate_invite"
              phx-submit="invite"
            />
            <p class="text-sm text-base-content/70">
              They'll get an email with a link to log in and join. Invitations expire after {Invitation.validity_days()} days.
            </p>
          </div>
          <p :if={@owner? and length(@members) > 1} class="text-sm text-base-content/70">
            To leave, make someone else the owner first.
          </p>
        </.section_card>

        <.section_card
          :if={@my_invitations != []}
          id="my-invitations"
          title="Invitations for you"
          help="To join another household, you'll need to leave this one first."
        >
          <.row_list id="my-invitation-list">
            <.list_row :for={invitation <- @my_invitations} id={"my-invitation-#{invitation.id}"}>
              {invitation.household.name}
              <:actions>
                <button
                  type="button"
                  class="btn btn-ghost"
                  phx-click="decline"
                  phx-value-id={invitation.id}
                >
                  Decline
                </button>
              </:actions>
            </.list_row>
          </.row_list>
        </.section_card>

        <.section_card
          :if={@owner?}
          id="transfer"
          title="Import and export"
          help="Download your recipes and meals as Cooklang files, to keep a copy or use them in other Cooklang apps, or import recipes and meals from such files."
        >
          <div class="flex flex-wrap gap-2">
            <a href={~p"/household/export"} id="export-household" class="btn" download>
              <.icon name="hero-arrow-down-tray" class="size-4" /> Export recipes and meals
            </a>
            <.link navigate={~p"/household/import"} id="import-household" class="btn">
              <.icon name="hero-arrow-up-tray" class="size-4" /> Import…
            </.link>
          </div>
        </.section_card>

        <.section_card
          :if={!@owner?}
          id="leave"
          title="Leave household"
          help="You'll lose access to its recipes, meals and plans."
          danger
        >
          <button
            type="button"
            id="leave-household"
            class="btn btn-outline btn-error"
            phx-click="leave"
            data-confirm={"Leave #{@current_scope.household.name}? You'll lose access to its recipes and plans."}
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Leave household
          </button>
        </.section_card>

        <.section_card
          :if={@owner? and !@confirm_delete?}
          id="delete-household"
          title="Delete household"
          help="Deletes every recipe, meal and plan, and removes all members. This can't be undone."
          danger
        >
          <button
            type="button"
            id="start-delete-household"
            class="btn btn-outline btn-error"
            phx-click="start_delete"
          >
            <.icon name="hero-trash" class="size-4" /> Delete household…
          </button>
        </.section_card>
        <.confirm_panel
          :if={@confirm_delete?}
          id="delete-household-panel"
          title={"Delete #{@current_scope.household.name}?"}
          confirm="Delete household"
          confirm_id="confirm-delete-household"
          form="delete-form"
          on_cancel="cancel_delete"
        >
          Deletes every recipe, meal and plan, and removes all members. This can't be undone.
          Type <strong>{@current_scope.household.name}</strong>
          to confirm.
          <:extra>
            <form id="delete-form" phx-submit="delete">
              <.input
                type="text"
                id="delete-confirmation"
                name="confirmation"
                value=""
                autocomplete="off"
                aria-label="Household name"
                phx-mounted={JS.focus()}
              />
            </form>
          </:extra>
        </.confirm_panel>
      </div>
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
     |> assign(editing_slot_id: nil, slot_form: nil, deleting_slot: nil, confirm_delete?: false)
     |> assign_new_slot_form(Households.change_meal_slot())
     |> assign_lists()
     |> assign_form(Households.change_household(scope.household))}
  end

  defp assign_lists(socket) do
    scope = socket.assigns.current_scope

    pending =
      if socket.assigns.owner?, do: Households.list_pending_invitations(scope), else: []

    meal_slots = Households.list_meal_slots(scope)

    assign(socket,
      meal_slots: meal_slots,
      missing_defaults: MealSlot.missing_defaults(meal_slots),
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

  def handle_event("adjust_feeding", %{"delta" => delta}, socket) do
    form = socket.assigns.form
    feeding = step_field(form[:usually_feeding], delta, 1, 50)

    changeset =
      socket.assigns.current_scope.household
      |> Households.change_household(Map.put(form.params, "usually_feeding", feeding))
      |> Map.put(:action, form.source.action)

    {:noreply, assign_form(socket, changeset)}
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

  def handle_event("validate_new_slot", %{"new_slot" => params}, socket) do
    changeset = Households.change_meal_slot(%MealSlot{}, params)
    {:noreply, assign_new_slot_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("create_slot", %{"new_slot" => params}, socket) do
    case Households.create_meal_slot(socket.assigns.current_scope, params) do
      {:ok, slot} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{slot.name} added.")
         |> assign_new_slot_form(Households.change_meal_slot())
         |> assign_lists()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_new_slot_form(socket, changeset)}

      {:error, _reason} ->
        {:noreply, slot_error(socket)}
    end
  end

  def handle_event("edit_slot", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.meal_slots, &(&1.id == id)) do
      %MealSlot{} = slot ->
        {:noreply,
         assign(socket,
           editing_slot_id: slot.id,
           slot_form: to_form(Households.change_meal_slot(slot), as: :slot)
         )}

      nil ->
        {:noreply, assign_lists(socket)}
    end
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, editing_slot_id: nil, slot_form: nil)}
  end

  def handle_event("validate_slot", %{"slot_id" => id, "slot" => params}, socket) do
    case Enum.find(socket.assigns.meal_slots, &(&1.id == id)) do
      %MealSlot{} = slot ->
        changeset = slot |> Households.change_meal_slot(params) |> Map.put(:action, :validate)
        {:noreply, assign(socket, slot_form: to_form(changeset, as: :slot))}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("rename_slot", %{"slot_id" => id, "slot" => params}, socket) do
    case Households.rename_meal_slot(socket.assigns.current_scope, id, params) do
      {:ok, slot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Renamed to #{slot.name}.")
         |> assign(editing_slot_id: nil, slot_form: nil)
         |> assign_lists()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, slot_form: to_form(changeset, as: :slot))}

      {:error, _reason} ->
        {:noreply, socket |> assign(editing_slot_id: nil, slot_form: nil) |> slot_error()}
    end
  end

  # Meals planned in the slot from today on need a decision first.
  def handle_event("delete_slot", %{"id" => id}, socket) do
    case Households.slot_deletion_preview(socket.assigns.current_scope, id) do
      {:ok, %{upcoming: []}} -> delete_slot(socket, id, nil)
      {:ok, preview} -> {:noreply, assign(socket, deleting_slot: preview)}
      {:error, _reason} -> {:noreply, slot_error(socket)}
    end
  end

  def handle_event("confirm_delete_slot", %{"upcoming" => choice}, socket) do
    %{slot: slot} = socket.assigns.deleting_slot
    choice = if choice == "remove", do: :remove, else: choice
    delete_slot(assign(socket, deleting_slot: nil), slot.id, choice)
  end

  def handle_event("cancel_delete_slot", _params, socket),
    do: {:noreply, assign(socket, deleting_slot: nil)}

  def handle_event("move_slot", %{"id" => id, "direction" => direction}, socket) do
    direction = if direction == "up", do: :up, else: :down

    case Households.move_meal_slot(socket.assigns.current_scope, id, direction) do
      {:ok, _ids} -> {:noreply, assign_lists(socket)}
      {:error, _reason} -> {:noreply, slot_error(socket)}
    end
  end

  def handle_event("reorder_slots", %{"ids" => ids}, socket) when is_list(ids) do
    case Households.reorder_meal_slots(socket.assigns.current_scope, ids) do
      {:ok, _ids} -> {:noreply, assign_lists(socket)}
      {:error, _reason} -> {:noreply, slot_error(socket)}
    end
  end

  def handle_event("restore_slots", _params, socket) do
    case Households.restore_default_meal_slots(socket.assigns.current_scope) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Restored #{count} default #{if count == 1, do: "slot", else: "slots"}."
         )
         |> assign_lists()}

      {:error, _reason} ->
        {:noreply, slot_error(socket)}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    case Households.remove_member(socket.assigns.current_scope, id) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Member removed.") |> assign_lists()}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Couldn't remove that member.") |> assign_lists()}
    end
  end

  def handle_event("transfer", %{"id" => id}, socket) do
    case Households.transfer_ownership(socket.assigns.current_scope, id) do
      {:ok, household} ->
        {:noreply,
         socket |> put_flash(:info, "Ownership transferred.") |> refresh_household(household)}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Couldn't transfer ownership.") |> assign_lists()}
    end
  end

  def handle_event("leave", _params, socket) do
    case Households.leave_household(socket.assigns.current_scope) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "You've left #{socket.assigns.current_scope.household.name}.")
         |> redirect(to: ~p"/welcome")}

      {:error, :owner_must_transfer} ->
        {:noreply, put_flash(socket, :error, "Make someone else the owner before leaving.")}

      {:error, _reason} ->
        {:noreply, redirect(socket, to: ~p"/welcome")}
    end
  end

  def handle_event("start_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete?: true)}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete?: false)}

  def handle_event("delete", %{"confirmation" => confirmation}, socket) do
    case Households.delete_household(socket.assigns.current_scope, confirmation) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "#{socket.assigns.current_scope.household.name} was deleted.")
         |> redirect(to: ~p"/welcome")}

      {:error, :confirmation_mismatch} ->
        {:noreply,
         put_flash(socket, :error, "The name you typed doesn't match. Nothing was deleted.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the owner can delete the household.")}
    end
  end

  # After a transfer the scope's household has a new owner, which changes
  # what this page shows.
  defp refresh_household(socket, household) do
    scope = %{socket.assigns.current_scope | household: household}

    socket
    |> assign(current_scope: scope, owner?: Households.owner?(scope))
    |> assign_lists()
    |> assign_form(Households.change_household(household))
  end

  # The scope's household is refreshed by the :require_household hook; keep
  # the form in step when the owner saved from another tab or device.
  @impl true
  def handle_info({:household_updated, household}, socket) do
    {:noreply, refresh_household(socket, household)}
  end

  # Another member left or was removed.
  def handle_info({:member_removed, _user_id}, socket), do: {:noreply, assign_lists(socket)}

  # Someone joined, or invitations changed (possibly from another device).
  def handle_info({:household_changed, _what}, socket), do: {:noreply, assign_lists(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset))

  defp delete_slot(socket, id, upcoming) do
    case Households.delete_meal_slot(socket.assigns.current_scope, id, upcoming) do
      {:ok, %{archived_at: nil} = slot} ->
        {:noreply, socket |> put_flash(:info, "#{slot.name} deleted.") |> assign_lists()}

      {:ok, slot} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{slot.name} removed. Past weeks still show it.")
         |> assign_lists()}

      {:error, :last_slot} ->
        {:noreply, put_flash(socket, :error, "A household needs at least one meal slot.")}

      {:error, _reason} ->
        {:noreply, slot_error(socket)}
    end
  end

  defp assign_new_slot_form(socket, changeset),
    do: assign(socket, new_slot_form: to_form(changeset, as: :new_slot))

  # Not the owner any more, or the slots changed on another device: show the
  # current list rather than guess.
  defp slot_error(socket) do
    socket
    |> put_flash(:error, "Couldn't change the meal slots; they may have just changed elsewhere.")
    |> assign_lists()
  end

  defp summary(owner?, members, invitations) do
    [
      if(owner?, do: "You're the owner", else: "Only the owner can change the details"),
      ngettext("1 member", "%{count} members", length(members)),
      invitations != [] && ngettext("1 invitation", "%{count} invitations", length(invitations))
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp member_role(member, scope) do
    role = if member.id == scope.household.owner_id, do: "Owner", else: "Member"
    if member.id == scope.user.id, do: role <> " · you", else: role
  end

  defp expires_in(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :day) do
      0 -> "expires today"
      1 -> "expires tomorrow"
      days -> "expires in #{days} days"
    end
  end
end
