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
    <Layouts.app flash={@flash} current_scope={@current_scope} section="plan" wide>
      <.page_header>
        <span id="week-title">{week_title(@week, @today)}</span>
        <:meta>{date_range(@week)}</:meta>
        <:actions>
          <%!-- A fixed toolbar: "Today" keeps its place when it isn't needed. --%>
          <nav class="flex items-center gap-1" aria-label="Weeks">
            <button
              :if={not Week.fully_planned?(@week) and @week.slots != []}
              type="button"
              id="copy-last-week"
              class="btn btn-ghost lg:btn-sm"
              phx-click="copy_week"
              phx-disable-with="Copying..."
            >
              <.icon name="hero-document-duplicate" class="size-4" /> Copy last week
            </button>
            <div class="join">
              <.link
                patch={week_path(Date.add(@week.start, -7))}
                id="previous-week"
                class="btn join-item btn-square lg:btn-sm"
                aria-label="Previous week"
              >
                <.icon name="hero-chevron-left" class="size-5" />
              </.link>
              <.link
                :if={@week.start != Planning.week_start(@today)}
                patch={week_path(Planning.week_start(@today))}
                id="this-week"
                class="btn join-item lg:btn-sm"
              >
                Today
              </.link>
              <span
                :if={@week.start == Planning.week_start(@today)}
                class="btn join-item btn-disabled lg:btn-sm"
                aria-hidden="true"
              >
                Today
              </span>
              <.link
                patch={week_path(Date.add(@week.start, 7))}
                id="next-week"
                class="btn join-item btn-square lg:btn-sm"
                aria-label="Next week"
              >
                <.icon name="hero-chevron-right" class="size-5" />
              </.link>
            </div>
          </nav>
        </:actions>
      </.page_header>

      <div id="week-progress" class="space-y-1.5">
        <div class="flex justify-between text-sm">
          <span>
            <span class="font-medium">{@week.planned} of {@week.cells}</span> slots planned
          </span>
          <span :if={Week.fully_planned?(@week)} class="font-medium text-success">
            <.icon name="hero-check-circle" class="size-4" /> All planned
          </span>
        </div>
        <progress
          class={[
            "progress h-1.5 w-full",
            if(Week.fully_planned?(@week), do: "progress-success", else: "progress-primary")
          ]}
          value={@week.planned}
          max={max(@week.cells, 1)}
          aria-label="Slots planned"
        ></progress>
      </div>

      <p :if={@week.slots == []} class="text-base-content/70">
        Your household has no meal slots. Add some on the <.link
          navigate={~p"/household"}
          class="link"
        >household page</.link>.
      </p>

      <%!-- Phones and tablets: jump to a day. --%>
      <nav
        :if={@week.slots != []}
        id="day-strip"
        aria-label="Days"
        class="sticky top-[calc(3.5rem+env(safe-area-inset-top))] z-20 lg:top-0 -mx-4 grid grid-cols-7 gap-1 border-b border-base-300 bg-base-100/95 px-4 py-2 backdrop-blur sm:-mx-6 sm:px-6 lg:-mx-10 lg:px-10 xl:hidden"
      >
        <a
          :for={day <- @week.days}
          href={"#day-#{day}"}
          aria-current={day == @today && "date"}
          aria-label={Calendar.strftime(day, "%A %-d %B")}
          class={[
            "flex min-h-12 flex-col items-center justify-center rounded-field text-sm",
            cond do
              day == @today -> "bg-primary font-semibold text-primary-content"
              Date.before?(day, @today) -> "text-base-content/60"
              true -> "font-medium"
            end
          ]}
        >
          <span>{Calendar.strftime(day, "%a") |> String.first()}</span>
          <span class="tabular-nums">{day.day}</span>
          <span class={[
            "size-1.5 rounded-full",
            cond do
              day_meals(@cells, day) == 0 -> "bg-transparent"
              day == @today -> "bg-primary-content"
              true -> "bg-primary"
            end
          ]}></span>
        </a>
      </nav>

      <%!-- Day cards on phones, two columns from 1024 px; from 1280 px seven columns whose slots line up as
           bands (each day is a subgrid of the same rows, see app.css). --%>
      <ol
        id="days"
        phx-hook=".ScrollToToday"
        data-rows={length(band_slots(@week, @cells)) + 1}
        class="grid gap-3 lg:grid-cols-2 lg:items-start xl:grid-cols-7 xl:items-stretch xl:gap-x-2 xl:gap-y-0"
      >
        <li
          :for={day <- @week.days}
          id={"day-#{day}"}
          data-today={day == @today && "true"}
          class={[
            "min-w-0 scroll-mt-36 rounded-box border bg-base-100 p-3 xl:px-2 xl:pt-2 xl:pb-3",
            if(day == @today, do: "border-primary ring-1 ring-primary/30", else: "border-base-300")
          ]}
        >
          <h2 class="flex items-center justify-between gap-2 xl:mb-1">
            <span class="flex items-baseline gap-2">
              <span class={["font-semibold", Date.before?(day, @today) && "text-base-content/70"]}>
                <span class="xl:hidden">{Calendar.strftime(day, "%A")}</span>
                <span class="hidden xl:inline">{Calendar.strftime(day, "%a")}</span>
              </span>
              <span class="whitespace-nowrap text-sm text-base-content/70 tabular-nums">
                <span class="xl:hidden">{Calendar.strftime(day, "%-d %b")}</span>
                <span class="hidden xl:inline">{day.day}</span>
              </span>
              <span :if={day == @today} class="badge badge-primary badge-sm">Today</span>
            </span>
            <button
              :if={collapsible_day?(day, @week, @today)}
              type="button"
              id={"toggle-day-#{day}"}
              class="btn btn-ghost btn-sm xl:hidden"
              phx-click="toggle_day"
              phx-value-date={day}
              aria-expanded={to_string(not collapsed?(day, @week, @today, @open_days))}
              aria-controls={"slots-#{day}"}
            >
              {if collapsed?(day, @week, @today, @open_days), do: "Show", else: "Hide"}
              <.icon
                name="hero-chevron-down"
                class={[
                  "size-4 transition-transform",
                  not collapsed?(day, @week, @today, @open_days) && "rotate-180"
                ]}
              />
            </button>
          </h2>
          <p
            :if={collapsed?(day, @week, @today, @open_days)}
            id={"summary-#{day}"}
            class="text-sm text-base-content/70 xl:hidden"
          >
            {day_summary(@cells, @skips, day)}
          </p>
          <ul
            id={"slots-#{day}"}
            class={[
              "mt-2 space-y-3 xl:contents",
              collapsed?(day, @week, @today, @open_days) && "hidden"
            ]}
          >
            <%= for slot <- band_slots(@week, @cells) do %>
              <%= if slot in display_slots(@week, @cells, day) do %>
                <li
                  id={"cell-#{day}-#{slot.id}"}
                  class="flex min-w-0 flex-col gap-1.5 sm:flex-row sm:items-start xl:flex-col xl:border-t xl:border-base-300 xl:pt-2 xl:pb-1"
                >
                  <span class="w-24 shrink-0 pt-1 text-xs font-semibold uppercase tracking-wide text-base-content/60 xl:w-auto xl:pt-0">
                    {slot.name}<span :if={slot.archived_at} class="normal-case tracking-normal"> (removed)</span>
                  </span>
                  <div class="min-w-0 flex-1 space-y-1.5 xl:w-full">
                    <ul :if={cell_meals(@cells, day, slot) != []} class="flex flex-col gap-1.5">
                      <li
                        :for={planned_meal <- cell_meals(@cells, day, slot)}
                        id={"planned-#{planned_meal.id}"}
                        class="min-w-0"
                      >
                        <.meal_chip
                          planned_meal={planned_meal}
                          cooks={cooks(@cooks, planned_meal)}
                          leftovers_title={leftovers_title(planned_meal)}
                        />
                      </li>
                    </ul>
                    <%= cond do %>
                      <% slot.archived_at -> %>
                      <% MapSet.member?(@skips, {day, slot.id}) -> %>
                        <div class="flex items-center gap-2 text-sm text-base-content/70">
                          <span class="italic">Skipped</span>
                          <button
                            type="button"
                            class="btn btn-ghost xl:btn-sm"
                            phx-click="unskip"
                            phx-value-date={day}
                            phx-value-slot={slot.id}
                          >
                            Undo
                          </button>
                        </div>
                      <% true -> %>
                        <div class="flex gap-1.5 xl:flex-col">
                          <button
                            type="button"
                            class={[
                              "btn border-dashed border-base-300 bg-transparent font-normal text-base-content/70 shadow-none hover:border-primary/50 hover:text-primary xl:btn-sm xl:w-full",
                              cell_meals(@cells, day, slot) == [] && "flex-1 sm:flex-none"
                            ]}
                            phx-click="add"
                            phx-value-date={day}
                            phx-value-slot={slot.id}
                            aria-label={"Add to #{slot.name} on #{Calendar.strftime(day, "%A")}"}
                          >
                            <.icon name="hero-plus" class="size-4" /> Add
                          </button>
                          <button
                            :if={cell_meals(@cells, day, slot) == []}
                            type="button"
                            class="btn btn-ghost font-normal text-base-content/70 xl:btn-sm xl:w-full"
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
              <% else %>
                <%!-- Keeps the bands lined up on desktop; nothing on phones. --%>
                <li class="hidden xl:block xl:border-t xl:border-base-300" aria-hidden="true"></li>
              <% end %>
            <% end %>
          </ul>
        </li>
      </ol>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToToday">
        // On phones and tablets the plan opens at today's card, below the sticky bars.
        export default {
          mounted() {
            if (!window.matchMedia("(max-width: 1279px)").matches) return
            const today = this.el.querySelector("[data-today]")
            if (today && today.previousElementSibling) today.scrollIntoView({block: "start"})
          }
        }
      </script>

      <.sheet
        :if={@sheet}
        id="plan-sheet"
        title={sheet_title(@sheet, @week)}
        on_close="close_sheet"
      >
        <%= case @sheet do %>
          <% %{mode: :add} -> %>
            <div class="space-y-4">
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm font-medium">Servings</span>
                <.stepper
                  id="add-servings"
                  label="servings"
                  value={@servings}
                  event="adjust_servings"
                />
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

  attr :planned_meal, :any, required: true
  attr :cooks, :any, required: true, doc: "servings cooked when more than planned, or nil"
  attr :leftovers_title, :string, default: nil

  # A planned meal: its name on its own line (up to three lines), then the
  # servings, a leftovers mark and what it cooks for.
  defp meal_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="edit"
      phx-value-id={@planned_meal.id}
      title={@planned_meal.meal.name}
      class="flex w-full min-w-0 cursor-pointer flex-col items-start gap-0.5 rounded-field border border-base-300 bg-base-200 px-2.5 py-1.5 text-left transition-colors hover:border-primary/40 hover:bg-base-300"
    >
      <span class="line-clamp-3 w-full break-words leading-snug">{@planned_meal.meal.name}</span>
      <span class="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-sm text-base-content/70">
        <span
          :if={@planned_meal.leftovers != []}
          class="leftovers text-primary"
          title={@leftovers_title}
        >
          ↺
        </span>
        <span class="tabular-nums">×{@planned_meal.servings}</span>
        <span
          :if={@cooks}
          class="cooks badge badge-primary badge-soft badge-sm"
          title={"Cooked for #{@cooks}, to leave leftovers"}
        >
          cooks {@cooks}
        </span>
      </span>
    </button>
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
          <span class="min-w-0 break-words font-medium">{source.planned_meal.meal.name}</span>
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
        <.stepper
          id="edit-servings"
          label="servings"
          value={@planned_meal.servings}
          event="set_servings"
        />
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
        <.button variant="neutral" class="mb-2">Move</.button>
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
        <.collapsible
          id="slot-meals"
          value="slot"
          on_toggle="toggle_section"
          title={"Meals for #{@slot_name}"}
          count={length(@results.slot_meals)}
          open={open?(@expanded, "slot", @query, @results.slot_meals)}
        >
          <ul class="divide-y divide-base-300">
            <.meal_choice :for={meal <- @results.slot_meals} meal={meal} />
            <li :if={@results.slot_meals == []} class="px-4 py-3 text-sm text-base-content/70">
              <%= if @query == "" do %>
                No meals tagged for {@slot_name} yet. Plan a recipe or a new meal here and it will be, or tag meals on their page.
              <% else %>
                No {@slot_name} meals match.
              <% end %>
            </li>
          </ul>
        </.collapsible>

        <.collapsible
          :if={@results.other_meals != []}
          id="other-meals"
          value="other"
          on_toggle="toggle_section"
          title="Other meals"
          count={length(@results.other_meals)}
          open={open?(@expanded, "other", @query, @results.other_meals)}
        >
          <ul class="divide-y divide-base-300">
            <.meal_choice :for={meal <- @results.other_meals} meal={meal} />
          </ul>
        </.collapsible>

        <.collapsible
          :if={@recipes? and @results.recipes != []}
          id="recipe-choices"
          value="recipes"
          on_toggle="toggle_section"
          title="Recipes"
          count={length(@results.recipes)}
          open={open?(@expanded, "recipes", @query, @results.recipes)}
        >
          <ul class="divide-y divide-base-300">
            <.list_row
              :for={recipe <- @results.recipes}
              id={"pick-recipe-#{recipe.id}"}
              title={recipe.name}
              phx-click="pick_recipe"
              phx-value-id={recipe.id}
            >
              {recipe.name}
              <:trailing><span class="badge badge-ghost badge-sm">recipe</span></:trailing>
            </.list_row>
          </ul>
        </.collapsible>

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

  attr :meal, :any, required: true

  defp meal_choice(assigns) do
    ~H"""
    <.list_row
      id={"pick-meal-#{@meal.id}"}
      title={@meal.name}
      phx-click="pick_meal"
      phx-value-id={@meal.id}
    >
      {@meal.name}
      <:trailing><span class="text-sm">{recipe_count(@meal.recipe_count)}</span></:trailing>
    </.list_row>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Plan",
       open_days: MapSet.new(),
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

  def handle_event("toggle_day", %{"date" => date}, socket) do
    case Date.from_iso8601(date) do
      {:ok, day} ->
        open = socket.assigns.open_days

        open =
          if MapSet.member?(open, day), do: MapSet.delete(open, day), else: MapSet.put(open, day)

        {:noreply, assign(socket, open_days: open)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_section", %{"group" => section}, socket)
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

  # Every slot shown on any day this week, so desktop rows line up across days.
  defp band_slots(week, cells) do
    retired =
      Enum.filter(week.retired_slots, fn slot ->
        Enum.any?(week.days, &Map.has_key?(cells, {&1, slot.id}))
      end)

    Enum.sort_by(week.slots ++ retired, & &1.position)
  end

  defp day_meals(cells, day) do
    Enum.sum(for {{^day, _slot_id}, meals} <- cells, do: length(meals))
  end

  # On phones, days already past in the current week fold to one line.
  defp collapsible_day?(day, week, today),
    do: Date.before?(day, today) and Planning.week_start(today) == week.start

  defp collapsed?(day, week, today, open_days),
    do: collapsible_day?(day, week, today) and not MapSet.member?(open_days, day)

  defp day_summary(cells, skips, day) do
    meals = day_meals(cells, day)
    skipped = Enum.count(skips, &match?({^day, _slot_id}, &1))

    [
      meals > 0 && "#{meals} #{if meals == 1, do: "meal", else: "meals"} planned",
      skipped > 0 && "#{skipped} skipped"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> "Nothing planned"
      parts -> Enum.join(parts, " · ")
    end
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
