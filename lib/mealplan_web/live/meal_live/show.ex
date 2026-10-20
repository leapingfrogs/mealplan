defmodule MealplanWeb.MealLive.Show do
  @moduledoc "A meal: rename it, and add, order and remove its recipes."
  use MealplanWeb, :live_view

  alias Mealplan.Meals
  alias Mealplan.Recipes

  @picker_size 8

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link navigate={~p"/meals"} class="text-sm text-base-content/60 hover:text-base-content">
        <.icon name="hero-arrow-left" class="size-4" /> Meals
      </.link>

      <%= if @rename_form do %>
        <.form
          for={@rename_form}
          id="rename-meal-form"
          phx-change="validate_name"
          phx-submit="rename"
          class="flex flex-wrap items-start gap-2"
        >
          <div class="flex-1 min-w-48">
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
        <.header>
          <span id="meal-name">{@meal.name}</span>
          <:subtitle>{recipe_summary(@meal.meal_recipes)}</:subtitle>
          <:actions>
            <.button id="rename-meal" phx-click="edit_name">
              <.icon name="hero-pencil-square" class="size-4" /> Rename
            </.button>
          </:actions>
        </.header>
      <% end %>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold">Recipes</h2>
        <p
          :if={@meal.meal_recipes == []}
          id="no-recipes"
          class="rounded-box border border-dashed border-base-300 px-4 py-6 text-center text-base-content/60"
        >
          No recipes. That's fine for meals like "Eat out"; add some below if you'll cook.
        </p>
        <ol
          :if={@meal.meal_recipes != []}
          id="meal-recipes"
          class="divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={{meal_recipe, index} <- Enum.with_index(@meal.meal_recipes)}
            id={"meal-recipe-#{meal_recipe.recipe_id}"}
            class="flex items-center gap-2 px-4 py-2 min-h-12"
          >
            <.link
              navigate={~p"/recipes/#{meal_recipe.recipe}"}
              class="min-w-0 flex-1 hover:underline"
            >
              <span class="block truncate font-medium">{meal_recipe.recipe.name}</span>
              <span class="text-sm text-base-content/60">Serves {meal_recipe.recipe.servings}</span>
            </.link>
            <span class="flex shrink-0 items-center">
              <button
                type="button"
                class="btn btn-ghost btn-sm btn-square"
                phx-click="move"
                phx-value-id={meal_recipe.recipe_id}
                phx-value-direction="up"
                disabled={index == 0}
                aria-label={"Move #{meal_recipe.recipe.name} up"}
              >
                <.icon name="hero-chevron-up" class="size-4" />
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm btn-square"
                phx-click="move"
                phx-value-id={meal_recipe.recipe_id}
                phx-value-direction="down"
                disabled={index == length(@meal.meal_recipes) - 1}
                aria-label={"Move #{meal_recipe.recipe.name} down"}
              >
                <.icon name="hero-chevron-down" class="size-4" />
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm text-error"
                phx-click="remove"
                phx-value-id={meal_recipe.recipe_id}
              >
                Remove
              </button>
            </span>
          </li>
        </ol>
      </section>

      <section class="space-y-3 pt-2">
        <h2 class="text-lg font-semibold">Add a recipe</h2>
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
        <ul
          :if={@candidates != []}
          id="recipe-candidates"
          class="divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={recipe <- @candidates}
            id={"candidate-#{recipe.id}"}
            class="flex items-center justify-between gap-3 px-4 py-2"
          >
            <span class="min-w-0 truncate">{recipe.name}</span>
            <button
              type="button"
              class="btn btn-sm btn-primary btn-soft"
              phx-click="add"
              phx-value-id={recipe.id}
            >
              <.icon name="hero-plus" class="size-4" /> Add
            </button>
          </li>
        </ul>
        <p :if={@candidates == []} id="no-candidates" class="text-sm text-base-content/60">
          <%= if @picker_query == "" do %>
            No more recipes to add.
          <% else %>
            No recipes match “{@picker_query}”.
          <% end %>
          <.link navigate={~p"/recipes/new"} class="link">Write a new recipe</.link>
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(page_title: meal.name, rename_form: nil, picker_query: "")
     |> assign_meal(meal)}
  end

  @impl true
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
    socket |> assign(meal: meal, page_title: meal.name) |> assign_candidates()
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

  defp recipe_summary([]), do: "No recipes"
  defp recipe_summary([_one]), do: "1 recipe"
  defp recipe_summary(recipes), do: "#{length(recipes)} recipes"
end
