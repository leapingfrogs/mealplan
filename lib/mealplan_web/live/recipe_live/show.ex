defmodule MealplanWeb.RecipeLive.Show do
  @moduledoc "A recipe to cook from: ingredients, cookware and the method."
  use MealplanWeb, :live_view

  import MealplanWeb.RecipeComponents

  alias Mealplan.Cooklang
  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="recipes" wide>
      <.page_header back={~p"/recipes"} back_label="Recipes">
        <span id="recipe-name">{@recipe.name}</span>
        <:meta>
          <%= for {part, index} <- Enum.with_index(meta(@recipe, @parsed)) do %>
            <span :if={index > 0} aria-hidden="true"> · </span>
            <%= case part do %>
              <% {:link, text, url} -> %>
                <a href={url} class="link" target="_blank" rel="noopener noreferrer">{text}</a>
              <% text -> %>
                {text}
            <% end %>
          <% end %>
          <span :if={@recipe.archived_at} id="archived-badge" class="badge badge-ghost badge-sm ml-1">
            archived
          </span>
        </:meta>
        <:actions :if={@recipe.archived_at}>
          <.button id="restore-recipe" phx-click="restore" variant="primary">
            <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
          </.button>
        </:actions>
        <:actions :if={is_nil(@recipe.archived_at)}>
          <.button navigate={~p"/recipes/#{@recipe}/edit"} id="edit-recipe">
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
        <:menu :if={is_nil(@recipe.archived_at) and @owner?}>
          <a href={~p"/recipes/#{@recipe}/download"} id="download-recipe" download>
            <.icon name="hero-arrow-down-tray" class="size-4" /> Download .cook file
          </a>
        </:menu>
        <:menu :if={is_nil(@recipe.archived_at)}>
          <button
            type="button"
            id="delete-recipe"
            class="text-error"
            phx-click={JS.push("delete") |> JS.remove_attribute("open", to: "#page-header-menu")}
          >
            <.icon name="hero-trash" class="size-4" /> Delete recipe
          </button>
        </:menu>
      </.page_header>

      <.confirm_panel
        :if={@deleting}
        id="delete-recipe-panel"
        title={if @deleting.archive?, do: "Archive this recipe?", else: "Delete this recipe?"}
        confirm={if @deleting.archive?, do: "Archive recipe", else: "Delete recipe"}
        confirm_id="confirm-delete-recipe"
        on_confirm="confirm_delete"
        on_cancel="cancel_delete"
      >
        <p :if={@deleting.meals != []}>It will be taken out of these meals:</p>
        <p :if={@deleting.archive?}>
          Past plans used it, so it will be archived: hidden from lists and pickers, but kept
          in history, and you can restore it.
        </p>
        <p :if={not @deleting.archive? and @deleting.meals == []}>
          It isn't in any meal or plan.
        </p>
        <:item :for={meal <- @deleting.meals}>{meal.name}</:item>
      </.confirm_panel>

      <.empty_state :if={@parsed.ingredients == [] and not steps?(@parsed)} id="empty-recipe">
        No method or ingredients yet.
        <:action :if={is_nil(@recipe.archived_at)}>
          <.button navigate={~p"/recipes/#{@recipe}/edit"}>Add them</.button>
        </:action>
      </.empty_state>

      <div class="grid gap-8 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:items-start lg:gap-12">
        <aside
          :if={@parsed.ingredients != [] or @parsed.cookware != []}
          class="space-y-6 lg:sticky lg:top-6"
        >
          <section :if={@parsed.ingredients != []} class="space-y-2">
            <h2 class="text-xl font-semibold">Ingredients</h2>
            <.ingredient_list id="ingredients" ingredients={@parsed.ingredients} />
          </section>

          <section :if={@parsed.cookware != []} class="space-y-2">
            <h2 class="text-xl font-semibold">You'll need</h2>
            <p id="cookware" class="text-base-content/80">
              {@parsed.cookware |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.join(", ")}
            </p>
          </section>
        </aside>

        <section :if={steps?(@parsed)} class="max-w-prose space-y-2 lg:col-start-2">
          <h2 class="text-xl font-semibold">Method</h2>
          <.method id="method" recipe={@parsed} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      assign(socket,
        deleting: nil,
        owner?: Mealplan.Households.owner?(socket.assigns.current_scope)
      )

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

  # Serves, then the time and source from the recipe's front matter (a web
  # address as a link).
  defp meta(recipe, parsed) do
    time = parsed.metadata["time"] || parsed.metadata["time required"]

    source =
      case parsed.metadata["source"] do
        "http" <> _rest = url -> {:link, URI.parse(url).host || url, url}
        other -> other
      end

    Enum.reject(["Serves #{recipe.servings}", time, source], &(&1 in [nil, ""]))
  end
end
