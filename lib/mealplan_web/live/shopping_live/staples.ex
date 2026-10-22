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
      <.link navigate={~p"/shopping"} class="text-sm text-base-content/60 hover:text-base-content">
        <.icon name="hero-arrow-left" class="size-4" /> Shopping
      </.link>

      <.header>
        Staples
        <:subtitle>
          Things you always have, like salt or olive oil. They're left off the shopping list.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="staple-form"
        phx-change="validate"
        phx-submit="add"
        class="flex items-start gap-2"
      >
        <div class="flex-1">
          <.input
            field={@form[:name]}
            placeholder="e.g. Salt"
            aria-label="Staple"
            autocomplete="off"
          />
        </div>
        <.button variant="primary" phx-disable-with="Adding...">
          <.icon name="hero-plus" class="size-4" /> Add
        </.button>
      </.form>

      <ul id="staple-list" class="divide-y divide-base-300 rounded-box border border-base-300">
        <li
          :for={staple <- @staples}
          id={"staple-#{staple.id}"}
          class="flex items-center justify-between gap-3 px-4 py-2"
        >
          <span class="min-w-0 truncate">{staple.name}</span>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-square shrink-0"
            phx-click="remove"
            phx-value-id={staple.id}
            aria-label={"Remove #{staple.name}"}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </li>
        <li :if={@staples == []} class="px-4 py-8 text-center text-base-content/60">
          No staples yet.
        </li>
      </ul>
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
