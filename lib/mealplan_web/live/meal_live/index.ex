defmodule MealplanWeb.MealLive.Index do
  @moduledoc "The household's meals: search them or start a new one."
  use MealplanWeb, :live_view

  alias Mealplan.Meals

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="meals">
      <.header>
        Meals
        <:subtitle>What you plan: one or more recipes, or none at all, like "Eat out".</:subtitle>
        <:actions>
          <.link navigate={~p"/meals/archived"} id="archived-meals" class="btn btn-ghost">
            Archived
          </.link>
        </:actions>
      </.header>

      <.form
        for={@form}
        id="new-meal-form"
        phx-change="validate"
        phx-submit="create"
        class="flex flex-wrap items-start gap-2"
      >
        <div class="flex-1 min-w-48">
          <.input
            field={@form[:name]}
            placeholder="New meal, e.g. Sunday roast"
            aria-label="New meal name"
            autocomplete="off"
          />
        </div>
        <.button variant="primary" phx-disable-with="Creating...">
          <.icon name="hero-plus" class="size-4" /> Create
        </.button>
      </.form>

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

      <ul
        id="meals"
        phx-update="stream"
        class="divide-y divide-base-300 rounded-box border border-base-300"
      >
        <li id="meals-empty" class="hidden only:block px-4 py-8 text-center text-base-content/60">
          <%= if @search == "" do %>
            No meals yet. Create one above, then add recipes to it.
          <% else %>
            No meals match “{@search}”.
          <% end %>
        </li>
        <li :for={{id, meal} <- @streams.meals} id={id}>
          <.link
            navigate={~p"/meals/#{meal}"}
            class="flex items-center justify-between gap-3 px-4 py-3 transition-colors hover:bg-base-200/60"
          >
            <span class="min-w-0">
              <span class="block truncate font-medium">{meal.name}</span>
              <span class="text-sm text-base-content/60">
                {recipes(meal.recipe_count)}<span :if={meal.slots != []}> · {Enum.map_join(
                  meal.slots,
                  ", ",
                  & &1.name
                )}</span>
              </span>
            </span>
            <.icon name="hero-chevron-right" class="size-4 shrink-0 opacity-40" />
          </.link>
        </li>
      </ul>
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
