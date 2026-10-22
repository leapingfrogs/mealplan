defmodule MealplanWeb.RecipeLive.Index do
  @moduledoc "The household's recipes, searchable by name or ingredient."
  use MealplanWeb, :live_view

  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="recipes">
      <.page_header>
        Recipes
        <:actions>
          <.button navigate={~p"/recipes/new"} variant="primary" id="new-recipe">
            <.icon name="hero-plus" class="size-4" /> New recipe
          </.button>
        </:actions>
        <:menu>
          <.link navigate={~p"/recipes/archived"} id="archived-recipes">
            <.icon name="hero-archive-box" class="size-4" /> Archived recipes
          </.link>
        </:menu>
      </.page_header>

      <.form for={@search_form} id="recipe-search" phx-change="search" phx-submit="search">
        <label class="input w-full">
          <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
          <input
            type="search"
            name="q"
            value={@search_form[:q].value}
            placeholder="Search by name or ingredient"
            autocomplete="off"
            phx-debounce="250"
            aria-label="Search recipes"
            class="grow"
          />
        </label>
      </.form>

      <.row_list id="recipes" phx-update="stream">
        <li id="recipes-empty" class="hidden only:block px-4 py-8 text-center text-base-content/70">
          <%= if @search == "" do %>
            No recipes yet. Add one to start planning with it.
          <% else %>
            No recipes match “{@search}”.
          <% end %>
        </li>
        <.list_row
          :for={{id, recipe} <- @streams.recipes}
          id={id}
          navigate={~p"/recipes/#{recipe}"}
          title={recipe.name}
        >
          {recipe.name}
          <:meta>Serves {recipe.servings} · {ingredients(recipe.ingredient_count)}</:meta>
        </.list_row>
      </.row_list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Recipes") |> load("")}
  end

  @impl true
  def handle_event("search", %{"q" => search}, socket), do: {:noreply, load(socket, search)}

  # Another member added or changed a recipe.
  @impl true
  def handle_info({:recipe_changed, _id}, socket),
    do: {:noreply, load(socket, socket.assigns.search)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket, search) do
    search = String.trim(search)

    socket
    |> assign(search: search, search_form: to_form(%{"q" => search}))
    |> stream(:recipes, Recipes.list_recipes(socket.assigns.current_scope, search), reset: true)
  end

  defp ingredients(1), do: "1 ingredient"
  defp ingredients(count), do: "#{count} ingredients"
end
