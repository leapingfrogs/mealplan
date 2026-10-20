defmodule MealplanWeb.PlanLive.Week do
  @moduledoc """
  The week plan: one card per day with the household's slots in order, the
  meals planned in each (↺ marks leftovers), and skipped slots. `/plan`
  opens on the default week (this week, or next once this one is fully
  planned); `/plan/:week` takes any date in the week (ISO 8601).

  Adding and editing planned meals come with the next tasks.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Planning.Week
  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 id="week-title" class="text-lg font-semibold leading-8">{week_title(@week, @today)}</h1>
          <p class="text-sm text-base-content/60">{date_range(@week)}</p>
        </div>
        <nav class="flex items-center gap-1" aria-label="Weeks">
          <.link
            patch={week_path(Date.add(@week.start, -7))}
            id="previous-week"
            class="btn btn-ghost btn-sm btn-square"
            aria-label="Previous week"
          >
            <.icon name="hero-chevron-left" class="size-5" />
          </.link>
          <.link
            :if={@week.start != Planning.week_start(@today)}
            patch={week_path(Planning.week_start(@today))}
            id="this-week"
            class="btn btn-ghost btn-sm"
          >
            This week
          </.link>
          <.link
            patch={week_path(Date.add(@week.start, 7))}
            id="next-week"
            class="btn btn-ghost btn-sm btn-square"
            aria-label="Next week"
          >
            <.icon name="hero-chevron-right" class="size-5" />
          </.link>
        </nav>
      </div>

      <div id="week-progress" class="space-y-1">
        <div class="flex justify-between text-sm">
          <span>
            <span class="font-medium">{@week.planned} of {@week.cells}</span> slots planned
          </span>
          <span :if={Week.fully_planned?(@week)} class="text-success font-medium">
            <.icon name="hero-check-circle" class="size-4" /> All planned
          </span>
        </div>
        <progress
          class={[
            "progress w-full",
            if(Week.fully_planned?(@week), do: "progress-success", else: "progress-primary")
          ]}
          value={@week.planned}
          max={max(@week.cells, 1)}
          aria-label="Slots planned"
        ></progress>
      </div>

      <p :if={@week.slots == []} class="text-base-content/60">
        Your household has no meal slots. Add some on the <.link
          navigate={~p"/household"}
          class="link"
        >household page</.link>.
      </p>

      <ol id="days" class="grid gap-3 lg:grid-cols-7 lg:gap-2">
        <li
          :for={day <- @week.days}
          id={"day-#{day}"}
          class={[
            "rounded-box border bg-base-100 p-3 lg:p-2",
            if(day == @today, do: "border-primary ring-1 ring-primary/30", else: "border-base-300"),
            Date.before?(day, @today) && "opacity-75"
          ]}
        >
          <h2 class="mb-2 flex items-baseline justify-between gap-2">
            <span class="font-semibold">{Calendar.strftime(day, "%A")}</span>
            <span class="whitespace-nowrap text-sm text-base-content/60">
              <span :if={day == @today} class="badge badge-primary badge-sm mr-1 lg:hidden">Today</span>{Calendar.strftime(
                day,
                "%-d %b"
              )}
            </span>
          </h2>
          <ul class="space-y-2">
            <li
              :for={slot <- @week.slots}
              id={"cell-#{day}-#{slot.id}"}
              class="group flex flex-col gap-1 sm:flex-row sm:items-start lg:flex-col"
            >
              <span class="w-24 shrink-0 pt-0.5 text-xs font-medium uppercase tracking-wide text-base-content/50 lg:w-auto">
                {slot.name}
              </span>
              <div class="min-w-0 flex-1 lg:w-full">
                <ul :if={cell_meals(@cells, day, slot) != []} class="mb-1 flex flex-wrap gap-1">
                  <li
                    :for={planned_meal <- cell_meals(@cells, day, slot)}
                    id={"planned-#{planned_meal.id}"}
                  >
                    <button
                      type="button"
                      phx-click="edit"
                      phx-value-id={planned_meal.id}
                      class="badge badge-lg h-auto min-h-8 max-w-full cursor-pointer gap-1 whitespace-normal border-base-300 bg-base-200 py-1 text-left transition-colors hover:border-primary/40 hover:bg-base-300"
                    >
                      <span
                        :if={planned_meal.leftovers != []}
                        class="leftovers text-primary"
                        title={leftovers_title(planned_meal)}
                      >
                        ↺
                      </span>
                      <span class="min-w-0 break-words">{planned_meal.meal.name}</span>
                      <span class="text-base-content/60 tabular-nums">×{planned_meal.servings}</span>
                    </button>
                  </li>
                </ul>
                <%= if MapSet.member?(@skips, {day, slot.id}) do %>
                  <div class="flex items-center gap-1 text-sm text-base-content/50">
                    <span class="italic">Skipped</span>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="unskip"
                      phx-value-date={day}
                      phx-value-slot={slot.id}
                    >
                      Undo
                    </button>
                  </div>
                <% else %>
                  <div class="flex gap-1 transition-opacity lg:opacity-0 lg:group-hover:opacity-100 lg:group-focus-within:opacity-100">
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-base-content/60"
                      phx-click="add"
                      phx-value-date={day}
                      phx-value-slot={slot.id}
                    >
                      <.icon name="hero-plus" class="size-3.5" /> Add
                    </button>
                    <button
                      :if={cell_meals(@cells, day, slot) == []}
                      type="button"
                      class="btn btn-ghost btn-xs text-base-content/50"
                      phx-click="skip"
                      phx-value-date={day}
                      phx-value-slot={slot.id}
                    >
                      Skip
                    </button>
                  </div>
                <% end %>
              </div>
            </li>
          </ul>
        </li>
      </ol>

      <.sheet :if={@sheet} id="plan-sheet" title={sheet_title(@sheet, @week)}>
        <%= case @sheet do %>
          <% %{mode: :add} -> %>
            <div class="space-y-4">
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm font-medium">Servings</span>
                <.stepper id="add-servings" value={@servings} event="adjust_servings" />
              </div>
              <.meal_picker query={@query} results={@results} recipes?={true} />
            </div>
          <% %{mode: :edit} -> %>
            <.edit_sheet
              planned_meal={sheet_meal(@sheet, @week)}
              slots={@week.slots}
              query={@query}
              results={@results}
              move_form={@move_form}
            />
        <% end %>
      </.sheet>
    </Layouts.app>
    """
  end

  attr :planned_meal, :any, required: true
  attr :slots, :list, required: true
  attr :query, :string, required: true
  attr :results, :map, required: true
  attr :move_form, :any, required: true

  defp edit_sheet(assigns) do
    ~H"""
    <div class="space-y-5">
      <p :if={@planned_meal.leftovers != []} id="sheet-leftovers" class="text-sm text-primary">
        ↺ {leftovers_title(@planned_meal)}
      </p>
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm font-medium">Servings</span>
        <.stepper id="edit-servings" value={@planned_meal.servings} event="set_servings" />
      </div>

      <details id="change-meal" class="group rounded-box border border-base-300">
        <summary class="flex cursor-pointer items-center justify-between px-3 py-2 text-sm font-medium">
          Change meal
          <.icon name="hero-chevron-down" class="size-4 transition-transform group-open:rotate-180" />
        </summary>
        <div class="px-3 pb-3">
          <.meal_picker query={@query} results={@results} recipes?={false} />
        </div>
      </details>

      <.form
        for={@move_form}
        id="move-form"
        phx-submit="move"
        class="grid grid-cols-[1fr_1fr_auto] items-end gap-2"
      >
        <.input field={@move_form[:date]} type="date" label="Move to" />
        <.input
          field={@move_form[:slot]}
          type="select"
          label="Slot"
          options={Enum.map(@slots, &{&1.name, &1.id})}
        />
        <.button class="btn mb-2">Move</.button>
      </.form>

      <button
        type="button"
        id="remove-planned-meal"
        class="btn btn-error btn-soft w-full"
        phx-click="remove"
        data-confirm={"Remove #{@planned_meal.meal.name} from the plan?"}
      >
        <.icon name="hero-trash" class="size-4" /> Remove from plan
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  # A bottom sheet on phones, a centred dialog on wider screens.
  defp sheet(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4"
      phx-window-keydown="close_sheet"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/40" phx-click="close_sheet" aria-hidden="true"></div>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        class="relative max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-base-100 p-4 pb-6 shadow-xl sm:max-w-md sm:rounded-2xl"
        phx-mounted={
          JS.transition(
            {"ease-out duration-200", "translate-y-6 opacity-0", "translate-y-0 opacity-100"}
          )
        }
      >
        <div class="mx-auto mb-3 h-1 w-10 rounded-full bg-base-300 sm:hidden" aria-hidden="true">
        </div>
        <div class="mb-4 flex items-start justify-between gap-2">
          <h2 id={"#{@id}-title"} class="text-lg font-semibold leading-7">{@title}</h2>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-square"
            phx-click="close_sheet"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :value, :integer, required: true
  attr :event, :string, required: true

  defp stepper(assigns) do
    ~H"""
    <div id={@id} class="join">
      <button
        type="button"
        class="btn join-item btn-sm btn-square"
        phx-click={@event}
        phx-value-delta="-1"
        disabled={@value <= 1}
        aria-label="Fewer servings"
      >
        <.icon name="hero-minus" class="size-4" />
      </button>
      <span class="join-item flex w-12 items-center justify-center border border-base-300 text-sm font-semibold tabular-nums">
        {@value}
      </span>
      <button
        type="button"
        class="btn join-item btn-sm btn-square"
        phx-click={@event}
        phx-value-delta="1"
        disabled={@value >= 100}
        aria-label="More servings"
      >
        <.icon name="hero-plus" class="size-4" />
      </button>
    </div>
    """
  end

  attr :query, :string, required: true
  attr :results, :map, required: true
  attr :recipes?, :boolean, required: true

  defp meal_picker(assigns) do
    ~H"""
    <div class="space-y-2">
      <form id="sheet-search" phx-change="sheet_search" phx-submit="sheet_search">
        <label class="input w-full">
          <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
          <input
            type="search"
            name="q"
            value={@query}
            placeholder={if @recipes?, do: "Search meals and recipes", else: "Search meals"}
            autocomplete="off"
            phx-debounce="200"
            phx-mounted={JS.focus()}
            aria-label="Search"
            class="grow"
          />
        </label>
      </form>
      <ul id="sheet-results" class="divide-y divide-base-300 rounded-box border border-base-300">
        <li :for={meal <- @results.meals} id={"pick-meal-#{meal.id}"}>
          <button
            type="button"
            class="flex w-full items-center justify-between gap-3 px-3 py-2 text-left transition-colors hover:bg-base-200"
            phx-click="pick_meal"
            phx-value-id={meal.id}
          >
            <span class="min-w-0 truncate">{meal.name}</span>
            <span class="shrink-0 text-xs text-base-content/50">{recipe_count(meal.recipe_count)}</span>
          </button>
        </li>
        <li :for={recipe <- (@recipes? && @results.recipes) || []} id={"pick-recipe-#{recipe.id}"}>
          <button
            type="button"
            class="flex w-full items-center justify-between gap-3 px-3 py-2 text-left transition-colors hover:bg-base-200"
            phx-click="pick_recipe"
            phx-value-id={recipe.id}
          >
            <span class="min-w-0 truncate">{recipe.name}</span>
            <span class="badge badge-ghost badge-sm shrink-0">recipe</span>
          </button>
        </li>
        <li :if={new_meal_name(@query, @results)} id="pick-new">
          <button
            type="button"
            class="flex w-full items-center gap-2 px-3 py-2 text-left text-primary transition-colors hover:bg-base-200"
            phx-click="pick_new"
          >
            <.icon name="hero-plus" class="size-4" /> New meal “{new_meal_name(@query, @results)}”
          </button>
        </li>
        <li
          :if={@results.meals == [] and (@results.recipes == [] or not @recipes?) and @query == ""}
          class="px-3 py-4 text-center text-sm text-base-content/60"
        >
          No meals yet. Type a name to create one.
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Plan",
       sheet: nil,
       servings: 1,
       query: "",
       results: %{meals: [], recipes: []},
       move_form: nil
     )}
  end

  @impl true
  def handle_params(%{"week" => week}, _uri, socket) do
    case Date.from_iso8601(week) do
      {:ok, date} ->
        start = Planning.week_start(date)

        if start == date,
          do: {:noreply, socket |> assign(sheet: nil) |> load(start)},
          else: {:noreply, push_patch(socket, to: week_path(start), replace: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "That isn't a date we recognise.")
         |> push_patch(to: ~p"/plan", replace: true)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket |> assign(sheet: nil) |> load(Planning.default_week(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("skip", %{"date" => date, "slot" => slot_id}, socket) do
    with {:ok, date} <- Date.from_iso8601(date),
         {:ok, _date} <- Planning.skip_slot(socket.assigns.current_scope, date, slot_id) do
      {:noreply, reload(socket)}
    else
      _error ->
        {:noreply, socket |> put_flash(:error, "Couldn't skip that slot.") |> reload()}
    end
  end

  def handle_event("unskip", %{"date" => date, "slot" => slot_id}, socket) do
    with {:ok, date} <- Date.from_iso8601(date),
         {:ok, _date} <- Planning.unskip_slot(socket.assigns.current_scope, date, slot_id) do
      {:noreply, reload(socket)}
    else
      _error -> {:noreply, reload(socket)}
    end
  end

  ## The sheet

  def handle_event("add", %{"date" => date, "slot" => slot_id}, socket) do
    with {:ok, date} <- Date.from_iso8601(date),
         true <- Enum.any?(socket.assigns.week.slots, &(&1.id == slot_id)) do
      {:noreply,
       socket
       |> assign(
         sheet: %{mode: :add, date: date, slot_id: slot_id},
         servings: socket.assigns.current_scope.household.usually_feeding
       )
       |> search("")}
    else
      _invalid -> {:noreply, socket}
    end
  end

  # Reloads first so the sheet never opens on a meal that has just gone.
  def handle_event("edit", %{"id" => id}, socket) do
    socket = reload(socket)

    case Enum.find(socket.assigns.week.planned_meals, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      planned_meal ->
        {:noreply,
         socket
         |> assign(sheet: %{mode: :edit, id: planned_meal.id}, move_form: move_form(planned_meal))
         |> search("")}
    end
  end

  def handle_event("close_sheet", _params, socket), do: {:noreply, assign(socket, sheet: nil)}

  def handle_event("sheet_search", %{"q" => query}, socket), do: {:noreply, search(socket, query)}

  def handle_event("adjust_servings", %{"delta" => delta}, socket) do
    {:noreply, assign(socket, servings: clamp_servings(socket.assigns.servings + to_int(delta)))}
  end

  def handle_event("set_servings", %{"delta" => delta}, socket) do
    case sheet_meal(socket.assigns.sheet, socket.assigns.week) do
      %{} = planned_meal ->
        servings = clamp_servings(planned_meal.servings + to_int(delta))

        socket.assigns.current_scope
        |> Planning.set_servings(planned_meal.id, servings)
        |> after_change(socket, close?: false)

      nil ->
        {:noreply, assign(socket, sheet: nil)}
    end
  end

  def handle_event("pick_meal", %{"id" => meal_id}, socket), do: pick(socket, {:meal, meal_id})

  def handle_event("pick_recipe", %{"id" => recipe_id}, socket),
    do: pick(socket, {:recipe, recipe_id})

  def handle_event("pick_new", _params, socket) do
    with name when is_binary(name) <- new_meal_name(socket.assigns.query, socket.assigns.results),
         {:ok, meal} <- Meals.create_meal(socket.assigns.current_scope, %{name: name}) do
      pick(socket, {:meal, meal.id})
    else
      _error -> {:noreply, put_flash(socket, :error, "Couldn't create that meal.")}
    end
  end

  def handle_event("move", %{"move" => %{"date" => date, "slot" => slot_id}}, socket) do
    with %{} = planned_meal <- sheet_meal(socket.assigns.sheet, socket.assigns.week),
         {:ok, date} <- Date.from_iso8601(date),
         {:ok, moved} <-
           Planning.move_planned_meal(
             socket.assigns.current_scope,
             planned_meal.id,
             date,
             slot_id
           ) do
      slot = Enum.find(socket.assigns.week.slots, &(&1.id == moved.meal_slot_id))

      {:noreply,
       socket
       |> put_flash(
         :info,
         "Moved to #{Calendar.strftime(moved.date, "%a %-d %b")}#{slot && ", " <> slot.name}."
       )
       |> assign(sheet: nil)
       |> reload()}
    else
      _error -> after_change({:error, :invalid}, socket, close?: false)
    end
  end

  def handle_event("remove", _params, socket) do
    case sheet_meal(socket.assigns.sheet, socket.assigns.week) do
      %{} = planned_meal ->
        socket.assigns.current_scope
        |> Planning.remove_planned_meal(planned_meal.id)
        |> after_change(socket, close?: true)

      nil ->
        {:noreply, assign(socket, sheet: nil)}
    end
  end

  # A meal or recipe chosen in the sheet: plan it (adding) or switch to it
  # (editing).
  defp pick(%{assigns: %{sheet: %{mode: :add} = sheet}} = socket, {kind, id}) do
    plan = if kind == :meal, do: &Planning.plan_meal/5, else: &Planning.plan_recipe/5

    socket.assigns.current_scope
    |> plan.(sheet.date, sheet.slot_id, id, socket.assigns.servings)
    |> after_change(socket, close?: true)
  end

  defp pick(%{assigns: %{sheet: %{mode: :edit}}} = socket, {:meal, meal_id}) do
    case sheet_meal(socket.assigns.sheet, socket.assigns.week) do
      %{} = planned_meal ->
        socket.assigns.current_scope
        |> Planning.change_meal(planned_meal.id, meal_id)
        |> after_change(socket, close?: true)

      nil ->
        {:noreply, assign(socket, sheet: nil)}
    end
  end

  defp pick(socket, _choice), do: {:noreply, socket}

  defp after_change({:ok, _changed}, socket, close?: close?) do
    socket = if close?, do: assign(socket, sheet: nil), else: socket
    {:noreply, reload(socket)}
  end

  defp after_change(_error, socket, _opts) do
    {:noreply,
     socket |> put_flash(:error, "Couldn't change the plan. Please try again.") |> reload()}
  end

  defp search(socket, query) do
    scope = socket.assigns.current_scope
    query = String.trim(query)

    assign(socket,
      query: query,
      results: %{
        meals: scope |> Meals.list_meals(query) |> Enum.take(8),
        recipes: scope |> Recipes.list_recipes(query) |> Enum.take(8)
      }
    )
  end

  defp move_form(planned_meal) do
    to_form(%{"date" => Date.to_iso8601(planned_meal.date), "slot" => planned_meal.meal_slot_id},
      as: :move
    )
  end

  defp clamp_servings(servings), do: servings |> max(1) |> min(100)

  defp to_int(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _other -> 0
    end
  end

  # Other members' changes: plans, meal names, slots, the household's time
  # zone (which moves "today").
  @impl true
  def handle_info({:plan_changed, start}, %{assigns: %{week: %Week{start: start}}} = socket),
    do: {:noreply, reload(socket)}

  def handle_info({:meal_changed, _id}, socket), do: {:noreply, reload(socket)}
  def handle_info({:household_changed, :meal_slots}, socket), do: {:noreply, reload(socket)}
  def handle_info({:household_updated, _household}, socket), do: {:noreply, reload(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp week_path(date), do: ~p"/plan/#{Date.to_iso8601(date)}"

  # Also closes an edit sheet whose planned meal has gone.
  defp reload(socket) do
    socket = load(socket, socket.assigns.week.start)

    case socket.assigns.sheet do
      %{mode: :edit} = sheet ->
        if sheet_meal(sheet, socket.assigns.week), do: socket, else: assign(socket, sheet: nil)

      _other ->
        socket
    end
  end

  defp load(socket, start) do
    scope = socket.assigns.current_scope
    week = Planning.get_week(scope, start)

    assign(socket,
      week: week,
      today: Planning.today(scope),
      cells: Enum.group_by(week.planned_meals, &{&1.date, &1.meal_slot_id}),
      skips: MapSet.new(week.skips, &{&1.date, &1.meal_slot_id}),
      page_title: "Week of " <> Calendar.strftime(start, "%-d %b")
    )
  end

  defp week_title(%Week{start: start}, today) do
    this_week = Planning.week_start(today)

    cond do
      start == this_week -> "This week"
      start == Date.add(this_week, 7) -> "Next week"
      start == Date.add(this_week, -7) -> "Last week"
      true -> "Week of " <> Calendar.strftime(start, "%-d %B")
    end
  end

  defp date_range(%Week{start: start}) do
    stop = Date.add(start, 6)
    Calendar.strftime(start, "%a %-d %b") <> " – " <> Calendar.strftime(stop, "%a %-d %b %Y")
  end

  defp cell_meals(cells, day, slot), do: Map.get(cells, {day, slot.id}, [])

  defp sheet_meal(%{mode: :edit, id: id}, week), do: Enum.find(week.planned_meals, &(&1.id == id))
  defp sheet_meal(_sheet, _week), do: nil

  defp sheet_title(%{mode: :add, date: date, slot_id: slot_id}, week) do
    slot = Enum.find(week.slots, &(&1.id == slot_id))
    "Add to #{slot && slot.name} on #{Calendar.strftime(date, "%A %-d %b")}"
  end

  defp sheet_title(%{mode: :edit} = sheet, week) do
    planned_meal = sheet_meal(sheet, week)
    slot = Enum.find(week.slots, &(&1.id == planned_meal.meal_slot_id))

    "#{planned_meal.meal.name}, #{Calendar.strftime(planned_meal.date, "%a %-d %b")}#{slot && " " <> String.downcase(slot.name)}"
  end

  defp recipe_count(0), do: "no recipes"
  defp recipe_count(1), do: "1 recipe"
  defp recipe_count(count), do: "#{count} recipes"

  # Offer to create a meal named as typed, unless one already has that name.
  defp new_meal_name(query, results) do
    taken? = Enum.any?(results.meals, &(String.downcase(&1.name) == String.downcase(query)))
    if query != "" and not taken?, do: query
  end

  defp leftovers_title(planned_meal) do
    planned_meal.leftovers
    |> Enum.map(&Calendar.strftime(&1.source_planned_meal.date, "%a %-d %b"))
    |> Enum.uniq()
    |> Enum.join(", ")
    |> then(&"Leftovers from #{&1}")
  end
end
