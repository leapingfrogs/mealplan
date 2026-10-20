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

      <section id="meal-slots-section" class="space-y-3 pt-4">
        <div class="flex items-center justify-between gap-2">
          <h2 class="text-lg font-semibold">Meal slots</h2>
          <button
            :if={@owner? and @missing_defaults != []}
            type="button"
            id="restore-default-slots"
            class="btn btn-ghost btn-sm"
            phx-click="restore_slots"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Restore defaults
          </button>
        </div>
        <p class="text-sm text-base-content/60">
          The times of day you plan meals for, in order.
          <span :if={@owner?} class="hidden sm:inline">Drag to reorder.</span>
        </p>
        <ol
          id="meal-slots"
          phx-hook=".SortableSlots"
          data-sortable={to_string(@owner? and is_nil(@editing_slot_id))}
          class="divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={{slot, index} <- Enum.with_index(@meal_slots)}
            id={"slot-#{slot.id}"}
            data-id={slot.id}
            draggable={if @owner? and is_nil(@editing_slot_id), do: "true"}
            class={[
              "flex items-center gap-2 px-4 py-2 min-h-12 transition-colors",
              @owner? && "hover:bg-base-200/60"
            ]}
          >
            <%= if @editing_slot_id == slot.id do %>
              <.form
                for={@slot_form}
                id="rename-slot-form"
                phx-change="validate_slot"
                phx-submit="rename_slot"
                class="flex flex-1 flex-wrap items-start gap-2"
              >
                <input type="hidden" name="slot_id" value={slot.id} />
                <div class="flex-1 min-w-40">
                  <.input
                    field={@slot_form[:name]}
                    aria-label="Meal slot name"
                    autocomplete="off"
                    phx-mounted={JS.focus()}
                  />
                </div>
                <.button variant="primary" phx-disable-with="Saving...">Save</.button>
                <button type="button" class="btn btn-ghost" phx-click="cancel_rename">
                  Cancel
                </button>
              </.form>
            <% else %>
              <.icon
                :if={@owner?}
                name="hero-bars-2"
                class="hidden sm:block size-5 shrink-0 cursor-grab text-base-content/40"
              />
              <span class="flex-1 min-w-0 truncate">{slot.name}</span>
              <span :if={@owner?} class="flex shrink-0 items-center">
                <button
                  type="button"
                  class="btn btn-ghost btn-sm btn-square"
                  phx-click="move_slot"
                  phx-value-id={slot.id}
                  phx-value-direction="up"
                  disabled={index == 0}
                  aria-label={"Move #{slot.name} earlier"}
                >
                  <.icon name="hero-chevron-up" class="size-4" />
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm btn-square"
                  phx-click="move_slot"
                  phx-value-id={slot.id}
                  phx-value-direction="down"
                  disabled={index == length(@meal_slots) - 1}
                  aria-label={"Move #{slot.name} later"}
                >
                  <.icon name="hero-chevron-down" class="size-4" />
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="edit_slot"
                  phx-value-id={slot.id}
                >
                  Rename
                </button>
                <button
                  :if={length(@meal_slots) > 1}
                  type="button"
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="delete_slot"
                  phx-value-id={slot.id}
                  data-confirm={"Delete the #{slot.name} slot?"}
                >
                  Delete
                </button>
              </span>
            <% end %>
          </li>
        </ol>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".SortableSlots">
          // Drag and drop reordering for the owner; phones use the up/down buttons.
          export default {
            mounted() {
              let dragged = null
              const rows = () => [...this.el.querySelectorAll("li[data-id]")]

              this.el.addEventListener("dragstart", e => {
                if (this.el.dataset.sortable !== "true") return
                dragged = e.target.closest("li[data-id]")
                if (!dragged) return
                e.dataTransfer.effectAllowed = "move"
                dragged.classList.add("opacity-50")
              })
              this.el.addEventListener("dragover", e => {
                if (!dragged) return
                e.preventDefault()
                const over = e.target.closest("li[data-id]")
                if (!over || over === dragged) return
                const box = over.getBoundingClientRect()
                const after = e.clientY > box.top + box.height / 2
                this.el.insertBefore(dragged, after ? over.nextSibling : over)
              })
              this.el.addEventListener("drop", e => e.preventDefault())
              this.el.addEventListener("dragend", () => {
                if (!dragged) return
                dragged.classList.remove("opacity-50")
                dragged = null
                this.pushEvent("reorder_slots", {ids: rows().map(li => li.dataset.id)})
              })
            }
          }
        </script>
        <div
          :if={@deleting_slot}
          id="delete-slot-panel"
          role="alert"
          class="space-y-3 rounded-box border border-warning/50 bg-warning/10 p-4"
        >
          <p class="text-sm">
            <strong>{@deleting_slot.slot.name}</strong>
            has {length(@deleting_slot.upcoming)} {if length(@deleting_slot.upcoming) == 1,
              do: "meal",
              else: "meals"} planned from today: {Enum.map_join(
              @deleting_slot.upcoming,
              ", ",
              &"#{&1.meal.name} (#{Calendar.strftime(&1.date, "%a %-d %b")})"
            )}.
            <span :if={@deleting_slot.archive?}>
              Past weeks will still show it.
            </span>
          </p>
          <form
            id="delete-slot-form"
            phx-submit="confirm_delete_slot"
            class="flex flex-wrap items-end gap-2"
          >
            <label class="flex-1 min-w-48">
              <span class="label mb-1 text-sm">Those meals</span>
              <select name="upcoming" class="select w-full">
                <option
                  :for={slot <- @meal_slots}
                  :if={slot.id != @deleting_slot.slot.id}
                  value={slot.id}
                >
                  Move to {slot.name}
                </option>
                <option value="remove">Remove them from the plan</option>
              </select>
            </label>
            <button type="button" class="btn btn-ghost" phx-click="cancel_delete_slot">
              Cancel
            </button>
            <button class="btn btn-error">Delete {@deleting_slot.slot.name}</button>
          </form>
        </div>
        <.form
          :if={@owner?}
          for={@new_slot_form}
          id="new-slot-form"
          phx-change="validate_new_slot"
          phx-submit="create_slot"
          class="flex flex-wrap items-start gap-2"
        >
          <div class="flex-1 min-w-48">
            <.input
              field={@new_slot_form[:name]}
              placeholder="Add a slot, e.g. Elevenses"
              aria-label="New meal slot name"
              autocomplete="off"
            />
          </div>
          <.button variant="primary" phx-disable-with="Adding...">Add</.button>
        </.form>
      </section>

      <section class="space-y-3 pt-4">
        <h2 class="text-lg font-semibold">Members</h2>
        <ul id="members" class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={member <- @members}
            id={"member-#{member.id}"}
            class="flex flex-wrap items-center justify-between gap-2 px-4 py-3"
          >
            <span class="min-w-0 truncate">
              {member.email}<span
                :if={member.id == @current_scope.user.id}
                class="text-base-content/60"
              > (you)</span>
            </span>
            <span :if={member.id == @current_scope.household.owner_id} class="badge badge-ghost">
              owner
            </span>
            <span :if={@owner? and member.id != @current_scope.household.owner_id} class="flex gap-1">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="transfer"
                phx-value-id={member.id}
                data-confirm={"Make #{member.email} the owner? You'll become a regular member."}
              >
                Make owner
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm text-error"
                phx-click="remove"
                phx-value-id={member.id}
                data-confirm={"Remove #{member.email} from the household?"}
              >
                Remove
              </button>
            </span>
          </li>
        </ul>
        <button
          :if={!@owner?}
          type="button"
          id="leave-household"
          class="btn btn-ghost btn-sm text-error"
          phx-click="leave"
          data-confirm={"Leave #{@current_scope.household.name}? You'll lose access to its recipes and plans."}
        >
          Leave household
        </button>
        <p :if={@owner? and length(@members) > 1} class="text-sm text-base-content/60">
          To leave, make someone else the owner first.
        </p>
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

      <section :if={@owner?} id="transfer" class="space-y-3 pt-4">
        <h2 class="text-lg font-semibold">Import and export</h2>
        <p class="text-sm text-base-content/60">
          Download your recipes and meals as Cooklang files, to keep a copy or use them in
          other Cooklang apps.
        </p>
        <a
          href={~p"/household/export"}
          id="export-household"
          class="btn btn-soft btn-primary"
          download
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Export recipes and meals
        </a>
      </section>

      <section :if={@owner?} id="delete-household" class="space-y-3 pt-8">
        <h2 class="text-lg font-semibold text-error">Delete household</h2>
        <p class="text-sm text-base-content/60">
          Deletes all of the household's recipes, meals and plans, and removes every member.
          This can't be undone. Type <strong>{@current_scope.household.name}</strong> to confirm.
        </p>
        <.form
          for={%{}}
          as={:delete}
          id="delete-form"
          phx-submit="delete"
          class="flex flex-wrap items-start gap-2"
        >
          <div class="flex-1 min-w-48">
            <.input
              type="text"
              id="delete-confirmation"
              name="confirmation"
              value=""
              autocomplete="off"
              aria-label="Household name"
            />
          </div>
          <.button class="btn btn-error">Delete household</.button>
        </.form>
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
     |> assign(editing_slot_id: nil, slot_form: nil, deleting_slot: nil)
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

  defp expires_in(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :day) do
      0 -> "expires today"
      1 -> "expires tomorrow"
      days -> "expires in #{days} days"
    end
  end
end
