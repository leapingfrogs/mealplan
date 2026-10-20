defmodule MealplanWeb.RecipeLive.Show do
  @moduledoc "A recipe to cook from: ingredients, cookware and the method."
  use MealplanWeb, :live_view

  import MealplanWeb.RecipeComponents

  alias Mealplan.Cooklang
  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link navigate={~p"/recipes"} class="text-sm text-base-content/60 hover:text-base-content">
        <.icon name="hero-arrow-left" class="size-4" /> Recipes
      </.link>

      <.header>
        <span id="recipe-name">{@recipe.name}</span>
        <:subtitle>Serves {@recipe.servings}</:subtitle>
        <:actions>
          <.button navigate={~p"/recipes/#{@recipe}/edit"} id="edit-recipe">
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.header>

      <div
        :if={@parsed.ingredients == [] and not steps?(@parsed)}
        id="empty-recipe"
        class="rounded-box border border-dashed border-base-300 px-4 py-8 text-center text-base-content/60"
      >
        No method or ingredients yet.
        <.link navigate={~p"/recipes/#{@recipe}/edit"} class="link">Add them</.link>
      </div>

      <section :if={@parsed.ingredients != []} class="space-y-2">
        <h2 class="text-lg font-semibold">Ingredients</h2>
        <.ingredient_list id="ingredients" ingredients={@parsed.ingredients} />
      </section>

      <section :if={@parsed.cookware != []} class="space-y-2">
        <h2 class="text-lg font-semibold">You'll need</h2>
        <p id="cookware" class="text-base-content/80">
          {@parsed.cookware |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.join(", ")}
        </p>
      </section>

      <section :if={steps?(@parsed)} class="space-y-2">
        <h2 class="text-lg font-semibold">Method</h2>
        <.method id="method" recipe={@parsed} />
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign_recipe(socket, Recipes.get_recipe!(socket.assigns.current_scope, id))}
  end

  # Another member edited this recipe.
  @impl true
  def handle_info({:recipe_changed, id}, %{assigns: %{recipe: %{id: id}}} = socket) do
    {:noreply, assign_recipe(socket, Recipes.get_recipe!(socket.assigns.current_scope, id))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_recipe(socket, recipe) do
    assign(socket, page_title: recipe.name, recipe: recipe, parsed: Cooklang.parse(recipe.source))
  end

  defp steps?(parsed), do: Enum.any?(parsed.sections, &(&1.blocks != []))
end
