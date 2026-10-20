defmodule MealplanWeb.RecipeLive.Index do
  @moduledoc "The household's recipes, searchable by name or ingredient."
  use MealplanWeb, :live_view

  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Recipes
        <:actions>
          <div class="flex gap-2">
            <.link navigate={~p"/recipes/archived"} id="archived-recipes" class="btn btn-ghost">
              Archived
            </.link>
            <.button navigate={~p"/recipes/new"} variant="primary" id="new-recipe">
              <.icon name="hero-plus" class="size-4" /> New recipe
            </.button>
          </div>
        </:actions>
      </.header>

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

      <ul
        id="recipes"
        phx-update="stream"
        class="divide-y divide-base-300 rounded-box border border-base-300"
      >
        <li id="recipes-empty" class="hidden only:block px-4 py-8 text-center text-base-content/60">
          <%= if @search == "" do %>
            No recipes yet. Add one to start planning with it.
          <% else %>
            No recipes match “{@search}”.
          <% end %>
        </li>
        <li :for={{id, recipe} <- @streams.recipes} id={id}>
          <.link
            navigate={~p"/recipes/#{recipe}"}
            class="flex items-center justify-between gap-3 px-4 py-3 transition-colors hover:bg-base-200/60"
          >
            <span class="min-w-0">
              <span class="block truncate font-medium">{recipe.name}</span>
              <span class="text-sm text-base-content/60">
                Serves {recipe.servings} · {ingredients(recipe.ingredient_count)}
              </span>
            </span>
            <.icon name="hero-chevron-right" class="size-4 shrink-0 opacity-40" />
          </.link>
        </li>
      </ul>
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
