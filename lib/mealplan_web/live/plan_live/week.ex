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
          <button
            :if={not Week.fully_planned?(@week) and @week.slots != []}
            type="button"
            id="copy-last-week"
            class="btn btn-ghost btn-sm"
            phx-click="copy_week"
            phx-disable-with="Copying..."
          >
            <.icon name="hero-document-duplicate" class="size-4" /> Copy last week
          </button>
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
              :for={slot <- display_slots(@week, @cells, day)}
              id={"cell-#{day}-#{slot.id}"}
              class="group flex flex-col gap-1 sm:flex-row sm:items-start lg:flex-col"
            >
              <span class="w-24 shrink-0 pt-0.5 text-xs font-medium uppercase tracking-wide text-base-content/50 lg:w-auto">
                {slot.name}<span :if={slot.archived_at} class="normal-case tracking-normal"> (removed)</span>
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
                      <span
                        :if={cooks(@cooks, planned_meal)}
                        class="cooks badge badge-primary badge-soft badge-sm"
                        title={"Cooked for #{cooks(@cooks, planned_meal)}, to leave leftovers"}
                      >
                        cooks {cooks(@cooks, planned_meal)}
                      </span>
                    </button>
                  </li>
                </ul>
                <%= cond do %>
                  <% slot.archived_at -> %>
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
              <div role="tablist" class="tabs tabs-box tabs-sm">
                <button
                  :for={{tab, label} <- [{"new", "Meals"}, {"leftovers", "Leftovers"}]}
                  type="button"
                  role="tab"
                  id={"sheet-tab-#{tab}"}
                  class={["tab flex-1", @tab == tab && "tab-active"]}
                  aria-selected={to_string(@tab == tab)}
                  phx-click="sheet_tab"
                  phx-value-tab={tab}
                >
                  {label}
                  <span :if={tab == "leftovers" and @sources != []} class="ml-1 opacity-60">
                    ({length(@sources)})
                  </span>
                </button>
              </div>
              <.meal_picker
                :if={@tab == "new"}
                query={@query}
                results={@results}
                recipes?={true}
                expanded={@expanded}
                slot_name={sheet_slot_name(@sheet, @week)}
              />
              <.leftover_picker :if={@tab == "leftovers"} sources={@sources} />
            </div>
          <% %{mode: :edit} -> %>
            <.edit_sheet
              planned_meal={sheet_meal(@sheet, @week)}
              slots={@week.slots}
              query={@query}
              results={@results}
              move_form={@move_form}
              sources={@sources}
              cooking={@cooking}
              pending_move={@pending_move}
              expanded={@expanded}
              slot_name={sheet_slot_name(@sheet, @week)}
            />
        <% end %>
      </.sheet>
    </Layouts.app>
    """
  end

  attr :sources, :list, required: true

  # Earlier meals (within 14 days) whose recipes can be eaten as leftovers.
  defp leftover_picker(assigns) do
    ~H"""
    <div id="leftover-sources" class="space-y-2">
      <p :if={@sources == []} class="py-4 text-center text-sm text-base-content/60">
        Nothing cooked in the 14 days before this to have leftovers from.
      </p>
      <section
        :for={source <- @sources}
        id={"source-#{source.planned_meal.id}"}
        class="rounded-box border border-base-300 p-3"
      >
        <div class="flex items-baseline justify-between gap-2">
          <span class="min-w-0 truncate font-medium">{source.planned_meal.meal.name}</span>
          <span class="shrink-0 text-xs text-base-content/60">{slot_label(source.planned_meal)}</span>
        </div>
        <div class="mt-2 flex flex-wrap gap-1">
          <button
            :if={length(source.recipes) > 1}
            type="button"
            class="btn btn-sm btn-primary btn-soft"
            phx-click="pick_leftovers"
            phx-value-source={source.planned_meal.id}
            phx-value-recipe="all"
          >
            ↺ All of it
          </button>
          <button
            :for={%{recipe: recipe, cooked_servings: cooked} <- source.recipes}
            type="button"
            id={"source-#{source.planned_meal.id}-#{recipe.id}"}
            class="btn btn-sm btn-ghost border-base-300"
            phx-click="pick_leftovers"
            phx-value-source={source.planned_meal.id}
            phx-value-recipe={recipe.id}
          >
            ↺ {recipe.name} <span class="text-xs font-normal opacity-60">cooks {cooked}</span>
          </button>
        </div>
      </section>
    </div>
    """
  end

  attr :planned_meal, :any, required: true
  attr :slots, :list, required: true
  attr :query, :string, required: true
  attr :results, :map, required: true
  attr :move_form, :any, required: true
  attr :sources, :list, required: true
  attr :cooking, :map, required: true
  attr :pending_move, :any, required: true
  attr :expanded, :any, required: true
  attr :slot_name, :string, required: true

  defp edit_sheet(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm font-medium">Servings</span>
        <.stepper id="edit-servings" value={@planned_meal.servings} event="set_servings" />
      </div>

      <section :if={@planned_meal.meal.meal_recipes != []} id="sheet-recipes" class="space-y-2">
        <h3 class="text-sm font-medium">Recipes</h3>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={%{recipe: recipe} <- @planned_meal.meal.meal_recipes}
            id={"sheet-recipe-#{recipe.id}"}
            class="space-y-1 px-3 py-2"
          >
            <%= case leftover_for(@planned_meal, recipe.id) do %>
              <% nil -> %>
                <div class="flex items-baseline justify-between gap-2">
                  <span class="font-medium">{recipe.name}</span>
                  <span class="text-right text-xs text-base-content/60">
                    {fresh_note(@planned_meal, recipe.id, @cooking)}
                  </span>
                </div>
                <div
                  :if={offers(@planned_meal, @sources, recipe.id) != []}
                  class="flex flex-wrap items-center gap-1"
                >
                  <span class="text-xs text-base-content/60">Use leftovers from</span>
                  <button
                    :for={source <- offers(@planned_meal, @sources, recipe.id)}
                    type="button"
                    id={"use-#{recipe.id}-#{source.planned_meal.id}"}
                    class="btn btn-xs btn-primary btn-soft"
                    phx-click="use_leftovers"
                    phx-value-source={source.planned_meal.id}
                    phx-value-recipe={recipe.id}
                  >
                    ↺ {slot_label(source.planned_meal)}
                  </button>
                </div>
              <% leftover -> %>
                <div class="flex items-center justify-between gap-2">
                  <span class="font-medium">
                    <span class="text-primary">↺</span> {recipe.name}
                  </span>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="make_fresh"
                    phx-value-recipe={recipe.id}
                  >
                    Make fresh
                  </button>
                </div>
                <p class="text-xs text-primary">
                  Leftovers from {slot_label(leftover.source_planned_meal)}
                </p>
            <% end %>
          </li>
        </ul>
      </section>

      <details id="change-meal" class="group rounded-box border border-base-300">
        <summary class="flex cursor-pointer items-center justify-between px-3 py-2 text-sm font-medium">
          Change meal
          <.icon name="hero-chevron-down" class="size-4 transition-transform group-open:rotate-180" />
        </summary>
        <div class="px-3 pb-3">
          <.meal_picker
            query={@query}
            results={@results}
            recipes?={false}
            expanded={@expanded}
            slot_name={@slot_name}
          />
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

      <div
        :if={@pending_move}
        id="confirm-move"
        role="alert"
        class="space-y-3 rounded-box border border-warning/50 bg-warning/10 p-4"
      >
        <p class="text-sm">{links_warning(@planned_meal)} Moving it may undo those leftover links.</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_move">Cancel</button>
          <button type="button" class="btn btn-sm btn-warning" phx-click="confirm_move">Move anyway</button>
        </div>
      </div>

      <button
        type="button"
        id="remove-planned-meal"
        class="btn btn-error btn-soft w-full"
        phx-click="remove"
        data-confirm={remove_confirmation(@planned_meal)}
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
  attr :expanded, :any, required: true
  attr :slot_name, :string, required: true

  # Meals for the slot first and open; other meals and recipes collapsed.
  # Searching opens any section with matches.
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

      <div id="sheet-results" class="space-y-2">
        <.pick_section
          id="slot-meals"
          name="slot"
          title={"Meals for #{@slot_name}"}
          count={length(@results.slot_meals)}
          open={open?(@expanded, "slot", @query, @results.slot_meals)}
        >
          <.meal_choice :for={meal <- @results.slot_meals} meal={meal} />
          <li :if={@results.slot_meals == []} class="px-3 py-3 text-sm text-base-content/60">
            <%= if @query == "" do %>
              No meals tagged for {@slot_name} yet. Plan a recipe or a new meal here and it will be, or tag meals on their page.
            <% else %>
              No {@slot_name} meals match.
            <% end %>
          </li>
        </.pick_section>

        <.pick_section
          :if={@results.other_meals != []}
          id="other-meals"
          name="other"
          title="Other meals"
          count={length(@results.other_meals)}
          open={open?(@expanded, "other", @query, @results.other_meals)}
        >
          <.meal_choice :for={meal <- @results.other_meals} meal={meal} />
        </.pick_section>

        <.pick_section
          :if={@recipes? and @results.recipes != []}
          id="recipe-choices"
          name="recipes"
          title="Recipes"
          count={length(@results.recipes)}
          open={open?(@expanded, "recipes", @query, @results.recipes)}
        >
          <li :for={recipe <- @results.recipes} id={"pick-recipe-#{recipe.id}"}>
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
        </.pick_section>

        <button
          :if={new_meal_name(@query, @results)}
          type="button"
          id="pick-new"
          class="flex w-full items-center gap-2 rounded-box border border-dashed border-primary/40 px-3 py-2 text-left text-primary transition-colors hover:bg-base-200"
          phx-click="pick_new"
        >
          <.icon name="hero-plus" class="size-4" /> New meal “{new_meal_name(@query, @results)}”
        </button>
      </div>
    </div>
    """
  end

  defp open?(expanded, name, query, items),
    do: MapSet.member?(expanded, name) or (query != "" and items != [])

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :title, :string, required: true
  attr :count, :integer, required: true
  attr :open, :boolean, required: true
  slot :inner_block, required: true

  defp pick_section(assigns) do
    ~H"""
    <section id={@id} class="overflow-hidden rounded-box border border-base-300">
      <button
        type="button"
        class="flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm font-medium transition-colors hover:bg-base-200"
        phx-click="toggle_section"
        phx-value-section={@name}
        aria-expanded={to_string(@open)}
      >
        <span>{@title} <span class="font-normal text-base-content/50">({@count})</span></span>
        <.icon
          name="hero-chevron-down"
          class={["size-4 transition-transform", @open && "rotate-180"]}
        />
      </button>
      <ul class={["divide-y divide-base-300 border-t border-base-300", !@open && "hidden"]}>
        {render_slot(@inner_block)}
      </ul>
    </section>
    """
  end

  attr :meal, :any, required: true

  defp meal_choice(assigns) do
    ~H"""
    <li id={"pick-meal-#{@meal.id}"}>
      <button
        type="button"
        class="flex w-full items-center justify-between gap-3 px-3 py-2 text-left transition-colors hover:bg-base-200"
        phx-click="pick_meal"
        phx-value-id={@meal.id}
      >
        <span class="min-w-0 truncate">{@meal.name}</span>
        <span class="shrink-0 text-xs text-base-content/50">{recipe_count(@meal.recipe_count)}</span>
      </button>
    </li>
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
       results: %{slot_meals: [], other_meals: [], recipes: []},
       expanded: MapSet.new(["slot"]),
       move_form: nil,
       tab: "new",
       sources: [],
       cooking: %{},
       cooks: %{},
       pending_move: nil
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

  def handle_event("copy_week", _params, socket) do
    {:ok, copied} = Planning.copy_week(socket.assigns.current_scope, socket.assigns.week.start)
    {:noreply, socket |> put_flash(:info, copied_message(copied)) |> reload()}
  end

  ## The sheet

  def handle_event("add", %{"date" => date, "slot" => slot_id}, socket) do
    with {:ok, date} <- Date.from_iso8601(date),
         true <- Enum.any?(socket.assigns.week.slots, &(&1.id == slot_id)) do
      {:noreply,
       socket
       |> assign(
         sheet: %{mode: :add, date: date, slot_id: slot_id},
         expanded: MapSet.new(["slot"]),
         servings: socket.assigns.current_scope.household.usually_feeding,
         tab: "new"
       )
       |> search("")
       |> assign_sources()}
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
         |> assign(
           sheet: %{mode: :edit, id: planned_meal.id},
           expanded: MapSet.new(["slot"]),
           move_form: move_form(planned_meal),
           pending_move: nil
         )
         |> search("")
         |> assign_sources()}
    end
  end

  def handle_event("close_sheet", _params, socket), do: {:noreply, assign(socket, sheet: nil)}

  def handle_event("toggle_section", %{"section" => section}, socket)
      when section in ~w(slot other recipes) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, section),
        do: MapSet.delete(expanded, section),
        else: MapSet.put(expanded, section)

    {:noreply, assign(socket, expanded: expanded)}
  end

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

  # Picking an existing meal doesn't tag it; a recipe planned directly or a
  # new meal is tagged with the slot, so the slot's list learns.
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

  # A meal with leftover links asks for confirmation first.
  def handle_event("move", %{"move" => %{"date" => _date, "slot" => _slot} = params}, socket) do
    planned_meal = sheet_meal(socket.assigns.sheet, socket.assigns.week)

    if planned_meal && linked?(planned_meal) && is_nil(socket.assigns.pending_move),
      do: {:noreply, assign(socket, pending_move: params)},
      else: move(socket, params)
  end

  def handle_event("confirm_move", _params, socket) do
    case socket.assigns.pending_move do
      nil -> {:noreply, socket}
      params -> move(socket, params)
    end
  end

  def handle_event("cancel_move", _params, socket),
    do: {:noreply, assign(socket, pending_move: nil)}

  def handle_event("sheet_tab", %{"tab" => tab}, socket) when tab in ~w(new leftovers),
    do: {:noreply, assign(socket, tab: tab)}

  def handle_event("pick_leftovers", %{"source" => source_id, "recipe" => recipe}, socket) do
    case socket.assigns.sheet do
      %{mode: :add, date: date, slot_id: slot_id} ->
        which = if recipe == "all", do: :all, else: recipe

        socket.assigns.current_scope
        |> Planning.plan_leftovers(date, slot_id, source_id, which, socket.assigns.servings)
        |> after_change(socket, close?: true)

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("use_leftovers", %{"source" => source_id, "recipe" => recipe_id}, socket) do
    with_sheet_meal(socket, fn planned_meal ->
      Planning.add_leftover(socket.assigns.current_scope, planned_meal.id, source_id, recipe_id)
    end)
  end

  def handle_event("make_fresh", %{"recipe" => recipe_id}, socket) do
    with_sheet_meal(socket, fn planned_meal ->
      Planning.remove_leftover(socket.assigns.current_scope, planned_meal.id, recipe_id)
    end)
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

  # The move itself, with a note when leftover links no longer applied.
  defp move(socket, %{"date" => date, "slot" => slot_id}) do
    scope = socket.assigns.current_scope

    with %{} = planned_meal <- sheet_meal(socket.assigns.sheet, socket.assigns.week),
         links = Planning.leftover_links(scope, planned_meal.id),
         {:ok, date} <- Date.from_iso8601(date),
         {:ok, moved} <-
           Planning.move_planned_meal(
             socket.assigns.current_scope,
             planned_meal.id,
             date,
             slot_id
           ) do
      slot = find_slot(socket.assigns.week, moved.meal_slot_id)

      {:noreply,
       socket
       |> put_flash(
         :info,
         "Moved to #{Calendar.strftime(moved.date, "%a %-d %b")}#{slot && ", " <> slot.name}." <>
           undone_links(links - Planning.leftover_links(scope, moved.id))
       )
       |> assign(sheet: nil, pending_move: nil)
       |> reload()}
    else
      _error -> after_change({:error, :invalid}, assign(socket, pending_move: nil), close?: false)
    end
  end

  defp undone_links(0), do: ""
  defp undone_links(1), do: " One leftover link no longer applied."
  defp undone_links(count), do: " #{count} leftover links no longer applied."

  defp with_sheet_meal(socket, change) do
    case sheet_meal(socket.assigns.sheet, socket.assigns.week) do
      nil -> {:noreply, assign(socket, sheet: nil)}
      planned_meal -> planned_meal |> change.() |> after_change(socket, close?: false)
    end
  end

  # A meal or recipe chosen in the sheet: plan it (adding) or switch to it
  # (editing).
  defp pick(%{assigns: %{sheet: %{mode: :add} = sheet}} = socket, {kind, id}) do
    plan = if kind == :meal, do: &Planning.plan_meal/6, else: &Planning.plan_recipe/6

    socket.assigns.current_scope
    |> plan.(sheet.date, sheet.slot_id, id, socket.assigns.servings, tag: true)
    |> after_change(socket, close?: true)
  end

  defp pick(%{assigns: %{sheet: %{mode: :edit}}} = socket, {:meal, meal_id}) do
    case sheet_meal(socket.assigns.sheet, socket.assigns.week) do
      %{} = planned_meal ->
        socket.assigns.current_scope
        |> Planning.change_meal(planned_meal.id, meal_id, tag: true)
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

    slot_id = sheet_slot_id(socket.assigns.sheet, socket.assigns.week)

    {slot_meals, other_meals} =
      scope
      |> Meals.list_meals(query)
      |> Enum.split_with(fn meal -> Enum.any?(meal.slots, &(&1.id == slot_id)) end)

    assign(socket,
      query: query,
      results: %{
        slot_meals: slot_meals,
        other_meals: other_meals,
        recipes: Recipes.list_recipes(scope, query)
      }
    )
  end

  # The slot the sheet is planning into, whose meals are listed first.
  defp sheet_slot_id(%{mode: :add, slot_id: slot_id}, _week), do: slot_id

  defp sheet_slot_id(%{mode: :edit} = sheet, week) do
    case sheet_meal(sheet, week) do
      nil -> nil
      planned_meal -> planned_meal.meal_slot_id
    end
  end

  defp sheet_slot_id(nil, _week), do: nil

  defp sheet_slot_name(sheet, week) do
    case find_slot(week, sheet_slot_id(sheet, week)) do
      nil -> "this slot"
      slot -> slot.name
    end
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
        if sheet_meal(sheet, socket.assigns.week),
          do: assign_sources(socket),
          else: assign(socket, sheet: nil)

      %{mode: :add} ->
        assign_sources(socket)

      nil ->
        socket
    end
  end

  # What the open sheet can take leftovers from.
  defp assign_sources(%{assigns: %{sheet: %{mode: :add} = sheet}} = socket) do
    assign(socket,
      sources: Planning.leftover_sources(socket.assigns.current_scope, sheet.date, sheet.slot_id)
    )
  end

  defp assign_sources(%{assigns: %{sheet: %{mode: :edit} = sheet}} = socket) do
    planned_meal = sheet_meal(sheet, socket.assigns.week)

    sources =
      Planning.leftover_sources(
        socket.assigns.current_scope,
        planned_meal.date,
        planned_meal.meal_slot_id,
        planned_meal.id
      )

    assign(socket, sources: sources)
  end

  defp load(socket, start) do
    scope = socket.assigns.current_scope
    week = Planning.get_week(scope, start)

    cooking =
      Map.new(Planning.cooking(week), &{{&1.planned_meal.id, &1.recipe.id}, &1.cooked_servings})

    assign(socket,
      week: week,
      today: Planning.today(scope),
      cells: Enum.group_by(week.planned_meals, &{&1.date, &1.meal_slot_id}),
      skips: MapSet.new(week.skips, &{&1.date, &1.meal_slot_id}),
      cooking: cooking,
      cooks: cooks_by_meal(week, cooking),
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

  # The most any recipe in a planned meal is cooked for, when that is more
  # than its planned servings (leftovers are taken from it).
  defp cooks_by_meal(week, cooking) do
    for planned_meal <- week.planned_meals,
        cooked = cooking_max(cooking, planned_meal),
        cooked > planned_meal.servings,
        into: %{},
        do: {planned_meal.id, cooked}
  end

  defp cooking_max(cooking, planned_meal) do
    planned_meal.meal.meal_recipes
    |> Enum.map(&Map.get(cooking, {planned_meal.id, &1.recipe_id}, 0))
    |> Enum.max(fn -> 0 end)
  end

  defp cooks(cooks, planned_meal), do: Map.get(cooks, planned_meal.id)

  defp linked?(planned_meal),
    do: planned_meal.leftovers != [] or planned_meal.leftovers_taken != []

  defp leftover_for(planned_meal, recipe_id),
    do: Enum.find(planned_meal.leftovers, &(&1.recipe_id == recipe_id))

  defp taken(planned_meal, recipe_id),
    do: for(l <- planned_meal.leftovers_taken, l.recipe_id == recipe_id, do: l.planned_meal)

  defp fresh_note(planned_meal, recipe_id, cooking) do
    case taken(planned_meal, recipe_id) do
      [] ->
        "cooked fresh"

      eaters ->
        "cooks #{Map.get(cooking, {planned_meal.id, recipe_id})} · leftovers for " <>
          Enum.map_join(eaters, ", ", &slot_label/1)
    end
  end

  # Earlier meals to take this recipe from, unless others take it from here.
  defp offers(planned_meal, sources, recipe_id) do
    if taken(planned_meal, recipe_id) == [],
      do:
        Enum.filter(sources, fn source ->
          Enum.any?(source.recipes, &(&1.recipe.id == recipe_id))
        end),
      else: []
  end

  defp slot_label(planned_meal) do
    Calendar.strftime(planned_meal.date, "%a %-d %b") <>
      " " <> String.downcase(planned_meal.meal_slot.name)
  end

  defp links_warning(planned_meal) do
    feeds =
      planned_meal.leftovers_taken |> Enum.map(& &1.planned_meal) |> Enum.uniq_by(& &1.id)

    sources =
      planned_meal.leftovers |> Enum.map(& &1.source_planned_meal) |> Enum.uniq_by(& &1.id)

    [
      feeds != [] && "Its leftovers feed #{Enum.map_join(feeds, ", ", &slot_label/1)}.",
      sources != [] && "It eats leftovers from #{Enum.map_join(sources, ", ", &slot_label/1)}."
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  defp remove_confirmation(planned_meal) do
    feeds =
      planned_meal.leftovers_taken |> Enum.map(& &1.planned_meal) |> Enum.uniq_by(& &1.id)

    case feeds do
      [] ->
        "Remove #{planned_meal.meal.name} from the plan?"

      feeds ->
        "Remove #{planned_meal.meal.name} from the plan? " <>
          "#{Enum.map_join(feeds, ", ", &slot_label/1)} will then be cooked fresh instead."
    end
  end

  defp copied_message(%{meals: 0, skips: 0}),
    do: "Nothing to copy: last week had nothing planned for this week's empty slots."

  defp copied_message(%{meals: meals, skips: skips, leftovers: leftovers}) do
    parts =
      Enum.filter(
        [
          meals > 0 && count(meals, "meal"),
          skips > 0 && count(skips, "skipped slot"),
          leftovers > 0 && count(leftovers, "leftover link")
        ],
        & &1
      )

    "Copied #{and_join(parts)} from last week."
  end

  defp and_join([only]), do: only
  defp and_join(parts), do: Enum.join(Enum.drop(parts, -1), ", ") <> " and " <> List.last(parts)

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"

  # Active slots, plus archived ones on days they still hold meals.
  defp display_slots(week, cells, day) do
    retired = Enum.filter(week.retired_slots, &Map.has_key?(cells, {day, &1.id}))
    Enum.sort_by(week.slots ++ retired, & &1.position)
  end

  defp find_slot(week, slot_id),
    do: Enum.find(week.slots ++ week.retired_slots, &(&1.id == slot_id))

  defp cell_meals(cells, day, slot), do: Map.get(cells, {day, slot.id}, [])

  defp sheet_meal(%{mode: :edit, id: id}, week), do: Enum.find(week.planned_meals, &(&1.id == id))
  defp sheet_meal(_sheet, _week), do: nil

  defp sheet_title(%{mode: :add, date: date, slot_id: slot_id}, week) do
    slot = find_slot(week, slot_id)
    "Add to #{slot && slot.name} on #{Calendar.strftime(date, "%A %-d %b")}"
  end

  defp sheet_title(%{mode: :edit} = sheet, week) do
    planned_meal = sheet_meal(sheet, week)
    slot = find_slot(week, planned_meal.meal_slot_id)

    "#{planned_meal.meal.name}, #{Calendar.strftime(planned_meal.date, "%a %-d %b")}#{slot && " " <> String.downcase(slot.name)}"
  end

  defp recipe_count(0), do: "no recipes"
  defp recipe_count(1), do: "1 recipe"
  defp recipe_count(count), do: "#{count} recipes"

  # Offer to create a meal named as typed, unless one already has that name.
  defp new_meal_name(query, results) do
    taken? =
      Enum.any?(
        results.slot_meals ++ results.other_meals,
        &(String.downcase(&1.name) == String.downcase(query))
      )

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
