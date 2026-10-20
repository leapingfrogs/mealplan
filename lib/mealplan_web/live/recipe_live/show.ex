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
        <:subtitle>
          Serves {@recipe.servings}
          <span :if={@recipe.archived_at} id="archived-badge" class="badge badge-ghost badge-sm ml-1">
            archived
          </span>
        </:subtitle>
        <:actions>
          <%= if @recipe.archived_at do %>
            <.button id="restore-recipe" phx-click="restore" variant="primary">
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
            </.button>
          <% else %>
            <div class="flex gap-2">
              <.button navigate={~p"/recipes/#{@recipe}/edit"} id="edit-recipe">
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.button>
              <button
                type="button"
                id="delete-recipe"
                class="btn btn-ghost text-error"
                phx-click="delete"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </button>
            </div>
          <% end %>
        </:actions>
      </.header>

      <div
        :if={@deleting}
        id="delete-recipe-panel"
        role="alert"
        class="space-y-3 rounded-box border border-warning/50 bg-warning/10 p-4"
      >
        <div class="space-y-1 text-sm">
          <p :if={@deleting.meals != []}>
            It will be taken out of {Enum.map_join(@deleting.meals, ", ", & &1.name)}.
          </p>
          <p :if={@deleting.archive?}>
            Past plans used it, so it will be archived: hidden from lists and pickers, but kept
            in history, and you can restore it.
          </p>
          <p :if={not @deleting.archive? and @deleting.meals == []}>
            It isn't in any meal or plan.
          </p>
        </div>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_delete">Cancel</button>
          <button
            type="button"
            id="confirm-delete-recipe"
            class="btn btn-sm btn-error"
            phx-click="confirm_delete"
          >
            {if @deleting.archive?, do: "Archive recipe", else: "Delete recipe"}
          </button>
        </div>
      </div>

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
    socket = assign(socket, deleting: nil)
    {:ok, assign_recipe(socket, Recipes.get_recipe!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:noreply,
     assign(socket,
       deleting: Recipes.deletion_preview(socket.assigns.current_scope, socket.assigns.recipe)
     )}
  end

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, deleting: nil)}

  def handle_event("confirm_delete", _params, socket) do
    %{recipe: recipe} = socket.assigns

    case Recipes.delete_recipe(socket.assigns.current_scope, recipe) do
      {:ok, :archived} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{recipe.name} archived. Past plans keep it.")
         |> push_navigate(to: ~p"/recipes")}

      {:ok, :deleted} ->
        {:noreply,
         socket |> put_flash(:info, "#{recipe.name} deleted.") |> push_navigate(to: ~p"/recipes")}

      {:error, _reason} ->
        {:noreply,
         socket |> assign(deleting: nil) |> put_flash(:error, "Couldn't delete that recipe.")}
    end
  end

  def handle_event("restore", _params, socket) do
    case Recipes.restore_recipe(socket.assigns.current_scope, socket.assigns.recipe.id) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{recipe.name} restored.")
         |> assign_recipe(Recipes.get_recipe!(socket.assigns.current_scope, recipe.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't restore that recipe.")}
    end
  end

  # Another member edited this recipe.
  @impl true
  def handle_info({:recipe_changed, id}, %{assigns: %{recipe: %{id: id}}} = socket) do
    {:noreply, assign_recipe(socket, Recipes.get_recipe!(socket.assigns.current_scope, id))}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket |> put_flash(:info, "That recipe was deleted.") |> push_navigate(to: ~p"/recipes")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_recipe(socket, recipe) do
    assign(socket, page_title: recipe.name, recipe: recipe, parsed: Cooklang.parse(recipe.source))
  end

  defp steps?(parsed), do: Enum.any?(parsed.sections, &(&1.blocks != []))
end
