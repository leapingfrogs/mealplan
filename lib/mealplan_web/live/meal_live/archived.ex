defmodule MealplanWeb.MealLive.Archived do
  @moduledoc "Archived meals (deleted after past plans used them), with Restore."
  use MealplanWeb, :live_view

  alias Mealplan.Meals

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link navigate={~p"/meals"} class="text-sm text-base-content/60 hover:text-base-content">
        <.icon name="hero-arrow-left" class="size-4" /> Meals
      </.link>

      <.header>
        Archived meals
        <:subtitle>Hidden from lists and pickers, but kept for past plans.</:subtitle>
      </.header>

      <p :if={@meals == []} id="no-archived" class="py-8 text-center text-base-content/60">
        Nothing archived.
      </p>
      <ul
        :if={@meals != []}
        id="archived"
        class="divide-y divide-base-300 rounded-box border border-base-300"
      >
        <li
          :for={meal <- @meals}
          id={"archived-#{meal.id}"}
          class="flex items-center justify-between gap-3 px-4 py-3"
        >
          <.link navigate={~p"/meals/#{meal}"} class="min-w-0 truncate hover:underline">
            {meal.name}
          </.link>
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            phx-click="restore"
            phx-value-id={meal.id}
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
    {:ok, socket |> assign(page_title: "Archived meals") |> load()}
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    case Meals.restore_meal(socket.assigns.current_scope, id) do
      {:ok, meal} ->
        {:noreply, socket |> put_flash(:info, "#{meal.name} restored.") |> load()}

      {:error, %Ecto.Changeset{data: meal}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Another meal is already called #{meal.name}. Rename it first.")
         |> load()}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Couldn't restore that.") |> load()}
    end
  end

  @impl true
  def handle_info({:meal_changed, _id}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket),
    do: assign(socket, meals: Meals.list_archived_meals(socket.assigns.current_scope))
end
