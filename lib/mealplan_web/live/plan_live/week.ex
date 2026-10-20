defmodule MealplanWeb.PlanLive.Week do
  @moduledoc """
  The week plan. Planning itself arrives with the Planning tasks; until then
  this shows the household's meal slots.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        This week
        <:subtitle>Week planning is coming soon. Your household's meal slots:</:subtitle>
      </.header>

      <ol id="meal-slots" class="divide-y divide-base-300 rounded-box border border-base-300">
        <li :for={slot <- @meal_slots} id={"meal-slot-#{slot.id}"} class="px-4 py-3">
          {slot.name}
        </li>
      </ol>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    meal_slots = Households.list_meal_slots(socket.assigns.current_scope)
    {:ok, assign(socket, page_title: "Plan", meal_slots: meal_slots)}
  end

  # The owner changed the slots, possibly while this page was open.
  @impl true
  def handle_info({:household_changed, :meal_slots}, socket) do
    {:noreply,
     assign(socket, meal_slots: Households.list_meal_slots(socket.assigns.current_scope))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
