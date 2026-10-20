defmodule MealplanWeb.PlanLive.Week do
  @moduledoc """
  The week plan: one card per day with the household's slots in order, the
  meals planned in each (↺ marks leftovers), and skipped slots. `/plan`
  opens on the default week (this week, or next once this one is fully
  planned); `/plan/:week` takes any date in the week (ISO 8601).

  Adding and editing planned meals come with the next tasks.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Planning
  alias Mealplan.Planning.Week

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
                <%= cond do %>
                  <% meals = Map.get(@cells, {day, slot.id}) -> %>
                    <ul class="flex flex-wrap gap-1">
                      <li
                        :for={planned_meal <- meals}
                        id={"planned-#{planned_meal.id}"}
                        class="badge badge-lg h-auto min-h-8 max-w-full gap-1 whitespace-normal border-base-300 bg-base-200 py-1 text-left"
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
                      </li>
                    </ul>
                  <% MapSet.member?(@skips, {day, slot.id}) -> %>
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
                  <% true -> %>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-base-content/50 opacity-100 transition-opacity lg:opacity-0 lg:group-hover:opacity-100 lg:focus:opacity-100"
                      phx-click="skip"
                      phx-value-date={day}
                      phx-value-slot={slot.id}
                    >
                      Skip
                    </button>
                <% end %>
              </div>
            </li>
          </ul>
        </li>
      </ol>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Plan")}

  @impl true
  def handle_params(%{"week" => week}, _uri, socket) do
    case Date.from_iso8601(week) do
      {:ok, date} ->
        start = Planning.week_start(date)

        if start == date,
          do: {:noreply, load(socket, start)},
          else: {:noreply, push_patch(socket, to: week_path(start), replace: true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "That isn't a date we recognise.")
         |> push_patch(to: ~p"/plan", replace: true)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load(socket, Planning.default_week(socket.assigns.current_scope))}
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

  defp reload(socket), do: load(socket, socket.assigns.week.start)

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

  defp leftovers_title(planned_meal) do
    planned_meal.leftovers
    |> Enum.map(&Calendar.strftime(&1.source_planned_meal.date, "%a %-d %b"))
    |> Enum.uniq()
    |> Enum.join(", ")
    |> then(&"Leftovers from #{&1}")
  end
end
