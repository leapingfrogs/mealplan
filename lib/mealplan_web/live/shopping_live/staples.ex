defmodule MealplanWeb.ShoppingLive.Staples do
  @moduledoc """
  The household's staples: ingredients it always has, left off the shopping
  list (iteration 4 design, "Staples"). Any member can change them.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Shopping

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="shopping">
      <.page_header back={~p"/shopping"} back_label="Shopping">
        Staples
        <:meta>
          Things you always have, like salt or olive oil. They're left off the shopping list.
        </:meta>
      </.page_header>

      <.add_form
        for={@form}
        id="staple-form"
        field={@form[:name]}
        label="Add a staple"
        placeholder="e.g. Salt"
        phx-change="validate"
        phx-submit="add"
      />

      <.row_list :if={@staples != []} id="staple-list">
        <.list_row :for={staple <- @staples} id={"staple-#{staple.id}"}>
          {staple.name}
          <:actions>
            <button
              type="button"
              class="btn btn-ghost btn-square"
              phx-click="remove"
              phx-value-id={staple.id}
              aria-label={"Remove #{staple.name}"}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </:actions>
        </.list_row>
      </.row_list>
      <.empty_state :if={@staples == []} id="no-staples">
        No staples yet. Add the things you never need to buy.
      </.empty_state>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Staples", form: to_form(Shopping.change_staple()))
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"staple" => params}, socket) do
    changeset = Shopping.change_staple(%Mealplan.Shopping.Staple{}, params)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("add", %{"staple" => params}, socket) do
    case Shopping.add_staple(socket.assigns.current_scope, params) do
      {:ok, _staple} ->
        {:noreply, socket |> assign(form: to_form(Shopping.change_staple())) |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    _ = Shopping.remove_staple(socket.assigns.current_scope, id)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({:shopping_changed, _household_id}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket),
    do: assign(socket, staples: Shopping.list_staples(socket.assigns.current_scope))
end
