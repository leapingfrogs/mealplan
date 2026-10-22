defmodule MealplanWeb.RecipeLive.Archived do
  @moduledoc "Archived recipes (deleted after past plans used them), with Restore."
  use MealplanWeb, :live_view

  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="recipes">
      <.link navigate={~p"/recipes"} class="text-sm text-base-content/60 hover:text-base-content">
        <.icon name="hero-arrow-left" class="size-4" /> Recipes
      </.link>

      <.header>
        Archived recipes
        <:subtitle>Hidden from lists and pickers, but kept for past plans.</:subtitle>
      </.header>

      <p :if={@recipes == []} id="no-archived" class="py-8 text-center text-base-content/60">
        Nothing archived.
      </p>
      <ul
        :if={@recipes != []}
        id="archived"
        class="divide-y divide-base-300 rounded-box border border-base-300"
      >
        <li
          :for={recipe <- @recipes}
          id={"archived-#{recipe.id}"}
          class="flex items-center justify-between gap-3 px-4 py-3"
        >
          <.link navigate={~p"/recipes/#{recipe}"} class="min-w-0 truncate hover:underline">
            {recipe.name}
          </.link>
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            phx-click="restore"
            phx-value-id={recipe.id}
          >
            <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
          </button>
        </li>
      </ul>
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
