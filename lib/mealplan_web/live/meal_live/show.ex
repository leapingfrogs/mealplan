defmodule MealplanWeb.MealLive.Show do
  @moduledoc "A meal: rename it, and add, order and remove its recipes."
  use MealplanWeb, :live_view

  alias Mealplan.Meals
  alias Mealplan.Recipes

  @picker_size 8

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="meals" wide>
      <%= if @rename_form do %>
        <.link
          navigate={~p"/meals"}
          class="inline-flex min-h-8 items-center gap-1.5 text-sm font-medium text-base-content/70 hover:text-base-content"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Meals
        </.link>
        <.form
          for={@rename_form}
          id="rename-meal-form"
          phx-change="validate_name"
          phx-submit="rename"
          class="flex flex-wrap items-start gap-2"
        >
          <div class="min-w-48 flex-1">
            <.input
              field={@rename_form[:name]}
              aria-label="Meal name"
              autocomplete="off"
              phx-mounted={JS.focus()}
            />
          </div>
          <.button variant="primary" phx-disable-with="Saving...">Save</.button>
          <button type="button" class="btn btn-ghost" phx-click="cancel_rename">Cancel</button>
        </.form>
      <% else %>
        <.page_header back={~p"/meals"} back_label="Meals">
          <span id="meal-name">{@meal.name}</span>
          <:meta>
            {recipe_summary(@meal.meal_recipes)}
            <span :if={@meal.archived_at} id="archived-badge" class="badge badge-ghost badge-sm ml-1">
              archived
            </span>
          </:meta>
          <:actions :if={@meal.archived_at}>
            <.button id="restore-meal" phx-click="restore" variant="primary">
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
            </.button>
          </:actions>
          <:actions :if={is_nil(@meal.archived_at)}>
            <.button id="rename-meal" phx-click="edit_name">
              <.icon name="hero-pencil-square" class="size-4" /> Rename
            </.button>
          </:actions>
          <:menu :if={is_nil(@meal.archived_at)}>
            <button
              type="button"
              id="delete-meal"
              class="text-error"
              phx-click={JS.push("delete") |> JS.remove_attribute("open", to: "#page-header-menu")}
            >
              <.icon name="hero-trash" class="size-4" /> Delete meal
            </button>
          </:menu>
        </.page_header>
      <% end %>

      <.confirm_panel
        :if={@deleting}
        id="delete-meal-panel"
        title={if @deleting.archive?, do: "Archive this meal?", else: "Delete this meal?"}
        confirm={if @deleting.archive?, do: "Archive meal", else: "Delete meal"}
        confirm_id="confirm-delete-meal"
        on_confirm="confirm_delete"
        on_cancel="cancel_delete"
      >
        <p :if={@deleting.upcoming != []}>
          It's planned on these days; they'll be removed from the plan:
        </p>
        <p :if={@deleting.archive?}>
          Past plans used it, so it will be archived: hidden from lists and pickers, but kept in
          history, and you can restore it.
        </p>
        <p :if={not @deleting.archive? and @deleting.upcoming == []}>It isn't in any plan.</p>
        <:item :for={planned <- @deleting.upcoming}>
          {Calendar.strftime(planned.date, "%a %-d %b")}, {String.downcase(planned.meal_slot.name)}
        </:item>
      </.confirm_panel>

      <section id="meal-slots" class="space-y-2">
        <h2 class="text-sm font-semibold">Suits</h2>
        <.chip_group label="Suits">
          <.chip
            :for={slot <- @all_slots}
            id={"suits-#{slot.id}"}
            pressed={tagged?(@meal, slot)}
            phx-click="toggle_slot"
            phx-value-id={slot.id}
            disabled={not is_nil(@meal.archived_at)}
          >
            {slot.name}
          </.chip>
        </.chip_group>
        <p :if={@meal.slots == []} class="text-sm text-base-content/70">
          Tag the slots this meal suits, and planning those slots lists it first.
        </p>
      </section>

      <div class="grid gap-8 lg:grid-cols-2 lg:items-start">
        <section class="space-y-3">
          <h2 class="text-xl font-semibold">Recipes in this meal</h2>
          <.empty_state :if={@meal.meal_recipes == []} id="no-recipes">
            No recipes. That's fine for meals like "Eat out"; add some if you'll cook.
          </.empty_state>
          <.row_list
            :if={@meal.meal_recipes != []}
            id="meal-recipes"
            phx-hook="Sortable"
            data-event="reorder_recipes"
            data-sortable={to_string(is_nil(@meal.archived_at))}
          >
            <.list_row
              :for={{meal_recipe, index} <- Enum.with_index(@meal.meal_recipes)}
              id={"meal-recipe-#{meal_recipe.recipe_id}"}
              sortable_id={if is_nil(@meal.archived_at), do: meal_recipe.recipe_id}
              navigate={~p"/recipes/#{meal_recipe.recipe}"}
              title={meal_recipe.recipe.name}
            >
              {meal_recipe.recipe.name}
              <:meta>Serves {meal_recipe.recipe.servings}</:meta>
              <:lead :if={is_nil(@meal.archived_at)}>
                <.icon
                  name="hero-bars-2"
                  class="hidden size-5 cursor-grab text-base-content/40 sm:block"
                />
              </:lead>
              <:actions :if={is_nil(@meal.archived_at)}>
                <button
                  type="button"
                  class="btn btn-ghost btn-square"
                  phx-click="move"
                  phx-value-id={meal_recipe.recipe_id}
                  phx-value-direction="up"
                  disabled={index == 0}
                  aria-label={"Move #{meal_recipe.recipe.name} up"}
                >
                  <.icon name="hero-chevron-up" class="size-5" />
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-square"
                  phx-click="move"
                  phx-value-id={meal_recipe.recipe_id}
                  phx-value-direction="down"
                  disabled={index == length(@meal.meal_recipes) - 1}
                  aria-label={"Move #{meal_recipe.recipe.name} down"}
                >
                  <.icon name="hero-chevron-down" class="size-5" />
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-square text-error"
                  phx-click="remove"
                  phx-value-id={meal_recipe.recipe_id}
                  aria-label={"Remove #{meal_recipe.recipe.name}"}
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </:actions>
            </.list_row>
          </.row_list>
        </section>

        <section :if={is_nil(@meal.archived_at)} class="space-y-3">
          <h2 class="text-xl font-semibold">Add a recipe</h2>
          <.form for={@picker_form} id="recipe-picker" phx-change="find" phx-submit="find">
            <label class="input w-full">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
              <input
                type="search"
                name="q"
                value={@picker_form[:q].value}
                placeholder="Search your recipes"
                autocomplete="off"
                phx-debounce="250"
                aria-label="Search recipes to add"
                class="grow"
              />
            </label>
          </.form>
          <.row_list :if={@candidates != []} id="recipe-candidates">
            <.list_row
              :for={recipe <- @candidates}
              id={"candidate-#{recipe.id}"}
              title={recipe.name}
            >
              {recipe.name}
              <:meta>Serves {recipe.servings}</:meta>
              <:actions>
                <button
                  type="button"
                  class="btn btn-outline btn-sm"
                  phx-click="add"
                  phx-value-id={recipe.id}
                  aria-label={"Add #{recipe.name}"}
                >
                  <.icon name="hero-plus" class="size-4" /> Add
                </button>
              </:actions>
            </.list_row>
          </.row_list>
          <p :if={@candidates == []} id="no-candidates" class="text-sm text-base-content/70">
            <%= if @picker_query == "" do %>
              No more recipes to add.
            <% else %>
              No recipes match “{@picker_query}”.
            <% end %>
            <.link navigate={~p"/recipes/new"} class="link">Write a new recipe</.link>
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(page_title: meal.name, rename_form: nil, picker_query: "", deleting: nil)
     |> assign_meal(meal)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:noreply,
     assign(socket,
       deleting: Meals.deletion_preview(socket.assigns.current_scope, socket.assigns.meal)
     )}
  end

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, deleting: nil)}

  def handle_event("confirm_delete", _params, socket) do
    %{meal: meal} = socket.assigns

    case Meals.delete_meal(socket.assigns.current_scope, meal) do
      {:ok, :archived} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{meal.name} archived. Past plans keep it.")
         |> push_navigate(to: ~p"/meals")}

      {:ok, :deleted} ->
        {:noreply,
         socket |> put_flash(:info, "#{meal.name} deleted.") |> push_navigate(to: ~p"/meals")}

      {:error, _reason} ->
        {:noreply,
         socket |> assign(deleting: nil) |> put_flash(:error, "Couldn't delete that meal.")}
    end
  end

  def handle_event("restore", _params, socket) do
    case Meals.restore_meal(socket.assigns.current_scope, socket.assigns.meal.id) do
      {:ok, meal} ->
        {:noreply, socket |> put_flash(:info, "#{meal.name} restored.") |> reload()}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Another meal is already called #{socket.assigns.meal.name}. Rename it first."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't restore that meal.")}
    end
  end

  def handle_event("edit_name", _params, socket) do
    {:noreply, assign(socket, rename_form: to_form(Meals.change_meal(socket.assigns.meal)))}
  end

  def handle_event("cancel_rename", _params, socket),
    do: {:noreply, assign(socket, rename_form: nil)}

  def handle_event("validate_name", %{"meal" => params}, socket) do
    changeset = socket.assigns.meal |> Meals.change_meal(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, rename_form: to_form(changeset))}
  end

  def handle_event("rename", %{"meal" => params}, socket) do
    case Meals.rename_meal(socket.assigns.current_scope, socket.assigns.meal.id, params) do
      {:ok, _meal} ->
        {:noreply, socket |> assign(rename_form: nil) |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, rename_form: to_form(changeset))}

      {:error, :not_found} ->
        {:noreply, gone(socket)}
    end
  end

  def handle_event("find", %{"q" => query}, socket) do
    {:noreply, socket |> assign(picker_query: String.trim(query)) |> assign_candidates()}
  end

  def handle_event("add", %{"id" => recipe_id}, socket) do
    socket.assigns.current_scope
    |> Meals.add_recipe(socket.assigns.meal.id, recipe_id)
    |> after_change(socket, "Couldn't add that recipe; it may already be in the meal.")
  end

  def handle_event("remove", %{"id" => recipe_id}, socket) do
    socket.assigns.current_scope
    |> Meals.remove_recipe(socket.assigns.meal.id, recipe_id)
    |> after_change(socket, "Couldn't remove that recipe.")
  end

  def handle_event("toggle_slot", %{"id" => slot_id}, socket) do
    %{meal: meal} = socket.assigns
    current = Enum.map(meal.slots, & &1.id)
    slot_ids = if slot_id in current, do: List.delete(current, slot_id), else: [slot_id | current]

    socket.assigns.current_scope
    |> Meals.set_slots(meal.id, slot_ids)
    |> after_change(socket, "Couldn't change the slots.")
  end

  # Dragged into a new order (wider screens).
  def handle_event("reorder_recipes", %{"ids" => ids}, socket) when is_list(ids) do
    socket.assigns.current_scope
    |> Meals.reorder_recipes(socket.assigns.meal.id, ids)
    |> after_change(socket, "Couldn't reorder: the meal changed meanwhile.")
  end

  def handle_event("move", %{"id" => recipe_id, "direction" => direction}, socket) do
    direction = if direction == "up", do: :up, else: :down

    socket.assigns.current_scope
    |> Meals.move_recipe(socket.assigns.meal.id, recipe_id, direction)
    |> after_change(socket, "Couldn't move that recipe.")
  end

  defp after_change({:ok, _meal}, socket, _error), do: {:noreply, reload(socket)}

  defp after_change({:error, _reason}, socket, error),
    do: {:noreply, socket |> put_flash(:error, error) |> reload()}

  # Another member changed this meal, or a recipe that might be in it.
  @impl true
  def handle_info({:meal_changed, id}, %{assigns: %{meal: %{id: id}}} = socket),
    do: {:noreply, reload(socket)}

  def handle_info({:recipe_changed, _id}, socket), do: {:noreply, reload(socket)}
  def handle_info({:household_changed, :meal_slots}, socket), do: {:noreply, reload(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp reload(socket) do
    assign_meal(socket, Meals.get_meal!(socket.assigns.current_scope, socket.assigns.meal.id))
  rescue
    Ecto.NoResultsError -> gone(socket)
  end

  defp gone(socket) do
    socket |> put_flash(:error, "That meal no longer exists.") |> push_navigate(to: ~p"/meals")
  end

  defp assign_meal(socket, meal) do
    socket
    |> assign(
      meal: meal,
      page_title: meal.name,
      all_slots: Mealplan.Households.list_meal_slots(socket.assigns.current_scope)
    )
    |> assign_candidates()
  end

  # Recipes matching the picker's search that aren't in the meal yet.
  defp assign_candidates(socket) do
    in_meal = MapSet.new(socket.assigns.meal.meal_recipes, & &1.recipe_id)

    candidates =
      socket.assigns.current_scope
      |> Recipes.list_recipes(socket.assigns.picker_query)
      |> Enum.reject(&MapSet.member?(in_meal, &1.id))
      |> Enum.take(@picker_size)

    assign(socket,
      candidates: candidates,
      picker_form: to_form(%{"q" => socket.assigns.picker_query})
    )
  end

  defp tagged?(meal, slot), do: Enum.any?(meal.slots, &(&1.id == slot.id))

  defp recipe_summary([]), do: "No recipes"
  defp recipe_summary([_one]), do: "1 recipe"
  defp recipe_summary(recipes), do: "#{length(recipes)} recipes"
end
