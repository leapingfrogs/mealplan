defmodule MealplanWeb.RecipeLive.Archived do
  @moduledoc "Archived recipes (deleted after past plans used them), with Restore."
  use MealplanWeb, :live_view

  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="recipes">
      <.page_header back={~p"/recipes"} back_label="Recipes">
        Archived recipes
        <:meta>Hidden from lists and pickers, but kept for past plans.</:meta>
      </.page_header>

      <.empty_state :if={@recipes == []} id="no-archived">Nothing archived.</.empty_state>

      <.row_list :if={@recipes != []} id="archived">
        <.list_row
          :for={recipe <- @recipes}
          id={"archived-#{recipe.id}"}
          navigate={~p"/recipes/#{recipe}"}
          title={recipe.name}
        >
          {recipe.name}
          <:actions>
            <button
              type="button"
              class="btn btn-ghost"
              phx-click="restore"
              phx-value-id={recipe.id}
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
            </button>
          </:actions>
        </.list_row>
      </.row_list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Archived recipes") |> load()}
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    case Recipes.restore_recipe(socket.assigns.current_scope, id) do
      {:ok, recipe} ->
        {:noreply, socket |> put_flash(:info, "#{recipe.name} restored.") |> load()}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Couldn't restore that.") |> load()}
    end
  end

  @impl true
  def handle_info({:recipe_changed, _id}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket),
    do: assign(socket, recipes: Recipes.list_archived_recipes(socket.assigns.current_scope))
end
