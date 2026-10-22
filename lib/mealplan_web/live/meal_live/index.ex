defmodule MealplanWeb.MealLive.Index do
  @moduledoc "The household's meals: search them or start a new one."
  use MealplanWeb, :live_view

  alias Mealplan.Meals

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="meals">
      <.page_header>
        Meals
        <:meta>What you plan: one or more recipes, or none at all, like "Eat out".</:meta>
        <:menu>
          <.link navigate={~p"/meals/archived"} id="archived-meals">
            <.icon name="hero-archive-box" class="size-4" /> Archived meals
          </.link>
        </:menu>
      </.page_header>

      <.add_form
        for={@form}
        id="new-meal-form"
        field={@form[:name]}
        label="New meal name"
        placeholder="New meal, e.g. Sunday roast"
        button="Create"
        phx-change="validate"
        phx-submit="create"
      />

      <.form for={@search_form} id="meal-search" phx-change="search" phx-submit="search">
        <label class="input w-full">
          <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
          <input
            type="search"
            name="q"
            value={@search_form[:q].value}
            placeholder="Search by meal or recipe"
            autocomplete="off"
            phx-debounce="250"
            aria-label="Search meals"
            class="grow"
          />
        </label>
      </.form>

      <.row_list id="meals" phx-update="stream">
        <li id="meals-empty" class="hidden only:block px-4 py-8 text-center text-base-content/70">
          <%= if @search == "" do %>
            No meals yet. Create one above, then add recipes to it.
          <% else %>
            No meals match “{@search}”.
          <% end %>
        </li>
        <.list_row
          :for={{id, meal} <- @streams.meals}
          id={id}
          navigate={~p"/meals/#{meal}"}
          title={meal.name}
        >
          {meal.name}
          <:meta>
            {recipes(meal.recipe_count)}<span :if={meal.slots != []}> · {Enum.map_join(
              meal.slots,
              ", ",
              & &1.name
            )}</span>
          </:meta>
        </.list_row>
      </.row_list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Meals", form: to_form(Meals.change_meal()))
     |> load("")}
  end

  @impl true
  def handle_event("search", %{"q" => search}, socket), do: {:noreply, load(socket, search)}

  def handle_event("validate", %{"meal" => params}, socket) do
    changeset = Meals.change_meal(%Mealplan.Meals.Meal{}, params)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("create", %{"meal" => params}, socket) do
    case Meals.create_meal(socket.assigns.current_scope, params) do
      {:ok, meal} -> {:noreply, push_navigate(socket, to: ~p"/meals/#{meal}")}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Another member added or changed a meal.
  @impl true
  def handle_info({:meal_changed, _id}, socket),
    do: {:noreply, load(socket, socket.assigns.search)}

  def handle_info({:household_changed, :meal_slots}, socket),
    do: {:noreply, load(socket, socket.assigns.search)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket, search) do
    search = String.trim(search)

    socket
    |> assign(search: search, search_form: to_form(%{"q" => search}))
    |> stream(:meals, Meals.list_meals(socket.assigns.current_scope, search), reset: true)
  end

  defp recipes(0), do: "No recipes"
  defp recipes(1), do: "1 recipe"
  defp recipes(count), do: "#{count} recipes"
end
