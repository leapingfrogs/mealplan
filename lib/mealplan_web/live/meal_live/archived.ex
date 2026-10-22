defmodule MealplanWeb.MealLive.Archived do
  @moduledoc "Archived meals (deleted after past plans used them), with Restore."
  use MealplanWeb, :live_view

  alias Mealplan.Meals

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="meals">
      <.page_header back={~p"/meals"} back_label="Meals">
        Archived meals
        <:meta>Hidden from lists and pickers, but kept for past plans.</:meta>
      </.page_header>

      <.empty_state :if={@meals == []} id="no-archived">Nothing archived.</.empty_state>

      <.row_list :if={@meals != []} id="archived">
        <.list_row
          :for={meal <- @meals}
          id={"archived-#{meal.id}"}
          navigate={~p"/meals/#{meal}"}
          title={meal.name}
        >
          {meal.name}
          <:actions>
            <button
              type="button"
              class="btn btn-ghost"
              phx-click="restore"
              phx-value-id={meal.id}
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
