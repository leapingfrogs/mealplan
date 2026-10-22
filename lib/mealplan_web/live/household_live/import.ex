defmodule MealplanWeb.HouseholdLive.Import do
  @moduledoc """
  Importing recipes and meals (owner only): upload files, review what will
  happen to each recipe and meal and choose (including the slots each meal
  is tagged with), then import everything chosen in one go (iteration 2 and
  3 designs, "Screens" and "Export and import").
  """
  use MealplanWeb, :live_view

  alias Mealplan.Households
  alias Mealplan.Transfer
  alias Mealplan.Transfer.ImportItem

  @action_labels %{
    add: "Add",
    skip: "Skip (keep ours)",
    replace: "Replace ours",
    keep_both: "Keep both",
    leave_out: "Leave out"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="household">
      <.page_header back={~p"/household"} back_label="Household">
        Import recipes and meals
        <:meta>
          A Mealplan export, Cooklang <code>.cook</code>
          recipes, a <code>.menu</code>
          of meals, or a zip of a recipe folder.
        </:meta>
      </.page_header>

      <%= case @step do %>
        <% :upload -> %>
          <.upload_step uploads={@uploads} />
        <% :preview -> %>
          <.preview_step
            import={@import}
            choices={@choices}
            slots={@slots}
            bulk_slots={@bulk_slots}
          />
        <% :done -> %>
          <.done_step summary={@summary} />
      <% end %>
    </Layouts.app>
    """
  end

  attr :uploads, :map, required: true

  defp upload_step(assigns) do
    ~H"""
    <form id="upload-form" phx-change="validate" phx-submit="read" class="space-y-4">
      <label
        for={@uploads.files.ref}
        phx-drop-target={@uploads.files.ref}
        class="flex min-h-56 w-full cursor-pointer flex-col items-center justify-center gap-2 rounded-box border-2 border-dashed border-base-300 bg-base-100 px-4 py-10 text-center transition-colors hover:border-primary/50 hover:bg-base-200/50 phx-drop-target-active:border-primary phx-drop-target-active:bg-primary/5"
      >
        <.icon name="hero-arrow-up-tray" class="size-8 text-base-content/50" />
        <span class="font-medium">Choose files or drop them here</span>
        <span class="text-sm text-base-content/70">.zip, .cook or .menu, up to 10 MB</span>
        <.live_file_input upload={@uploads.files} class="sr-only" />
      </label>

      <.row_list :if={@uploads.files.entries != []} id="chosen-files">
        <.list_row :for={entry <- @uploads.files.entries} id={"file-#{entry.ref}"}>
          {entry.client_name}
          <:lead><.icon name="hero-document" class="size-5 text-base-content/50" /></:lead>
          <:meta :if={upload_errors(@uploads.files, entry) != []}>
            <span :for={error <- upload_errors(@uploads.files, entry)} class="text-error">
              {upload_error(error)}
            </span>
          </:meta>
          <:actions>
            <button
              type="button"
              class="btn btn-ghost btn-square"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              aria-label={"Remove #{entry.client_name}"}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </:actions>
        </.list_row>
      </.row_list>
      <p :for={error <- upload_errors(@uploads.files)} class="text-sm text-error">
        {upload_error(error)}
      </p>

      <div class="flex justify-end">
        <.button
          variant="primary"
          id="read-files"
          disabled={@uploads.files.entries == []}
          phx-disable-with="Reading…"
        >
          Continue
        </.button>
      </div>
    </form>
    """
  end

  attr :import, :any, required: true
  attr :choices, :map, required: true
  attr :slots, :list, required: true
  attr :bulk_slots, :list, required: true

  defp preview_step(assigns) do
    ~H"""
    <p id="import-counts" class="mb-4 text-base-content/80">{counts(@import)}</p>

    <form id="import-choices" phx-change="choose" phx-submit="apply" class="space-y-4">
      <.section_card :if={@import.recipes != []} id="import-recipes" title="Recipes">
        <.row_list id="import-recipe-list">
          <li :for={item <- @import.recipes} id={"item-#{item.key}"} class="space-y-2 px-4 py-3">
            <.item_row item={item} choice={@choices[item.key]}>
              <:detail>
                Serves {item.servings}
                <span :if={item.existing} class="text-warning">· we already have {item.existing.name}</span>
              </:detail>
            </.item_row>
            <details :if={item.imported.warnings != []} class="text-sm text-warning">
              <summary class="cursor-pointer">
                {length(item.imported.warnings)} {if length(item.imported.warnings) == 1,
                  do: "problem",
                  else: "problems"} in the recipe (it can still be imported)
              </summary>
              <ul class="mt-1 list-disc pl-5">
                <li :for={warning <- item.imported.warnings}>
                  <span :if={warning.line}>Line {warning.line}:</span> {warning.message}
                </li>
              </ul>
            </details>
          </li>
        </.row_list>
      </.section_card>

      <.section_card :if={@import.meals != []} id="import-meals" title="Meals">
        <div
          :if={@slots != [] and untagged(@import, @choices) != []}
          id="bulk-slots"
          class="space-y-3 rounded-box bg-base-200/60 p-4"
        >
          <p class="text-sm">
            Set slots for meals without any
            <span class="text-base-content/70">
              ({plural(length(untagged(@import, @choices)), "meal")})
            </span>
          </p>
          <.slot_chips
            id="bulk"
            slots={@slots}
            chosen={@bulk_slots}
            event="toggle_bulk_slot"
            key="bulk"
          />
          <div class="flex flex-wrap items-center gap-3">
            <button
              type="button"
              id="apply-bulk-slots"
              class="btn"
              phx-click="apply_bulk_slots"
              disabled={@bulk_slots == []}
            >
              Set for {plural(length(untagged(@import, @choices)), "meal")}
            </button>
            <span :if={@bulk_slots == []} class="text-sm text-base-content/70">
              Choose slots first.
            </span>
          </div>
        </div>
        <.row_list id="import-meal-list">
          <li :for={item <- @import.meals} id={"item-#{item.key}"} class="space-y-2 px-4 py-3">
            <.item_row item={item} choice={@choices[item.key]}>
              <:detail>
                {references(item, @import, @choices)}
                <span :if={item.existing} class="text-warning">· we already have this meal</span>
              </:detail>
            </.item_row>
            <div :if={@slots != [] and tags?(@choices[item.key])} class="space-y-1">
              <.slot_chips
                id={item.key}
                slots={@slots}
                chosen={item.slot_ids}
                event="toggle_slot"
                key={item.key}
              />
              <p
                :if={item.unmatched_slots != []}
                id={"unmatched-#{item.key}"}
                class="text-sm text-warning"
              >
                {Enum.map_join(item.unmatched_slots, ", ", &"#{&1}: no such slot")}
              </p>
            </div>
          </li>
        </.row_list>
      </.section_card>

      <.empty_state :if={@import.recipes == [] and @import.meals == []} id="nothing-to-import">
        Nothing to import in those files.
      </.empty_state>

      <.section_card
        :if={@import.problems != []}
        id="import-problems"
        title="Not imported"
        help="These files or parts of them couldn't be read."
      >
        <ul class="space-y-2 text-sm">
          <li :for={problem <- @import.problems} class="flex gap-2">
            <.icon name="hero-exclamation-triangle" class="size-4 shrink-0 mt-0.5 text-warning" />
            <span><span class="font-medium">{problem.file}</span> {problem.message}</span>
          </li>
        </ul>
      </.section_card>

      <div class="flex flex-wrap justify-end gap-2">
        <button type="button" id="cancel-import" class="btn btn-ghost" phx-click="start_over">
          Start over
        </button>
        <.button
          :if={@import.recipes != [] or @import.meals != []}
          variant="primary"
          id="apply-import"
          phx-disable-with="Importing…"
        >
          Import
        </.button>
      </div>
    </form>
    """
  end

  attr :item, ImportItem, required: true
  attr :choice, :atom, required: true
  slot :detail

  defp item_row(assigns) do
    assigns =
      assign(
        assigns,
        :options,
        Enum.map(ImportItem.actions(assigns.item), &{@action_labels[&1], &1})
      )

    ~H"""
    <div class="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-3">
      <div class="min-w-0">
        <p class={[
          "break-words font-medium",
          @choice == :leave_out && "text-base-content/40 line-through"
        ]}>
          {@item.imported.name}
        </p>
        <p class="text-sm text-base-content/70">{render_slot(@detail)}</p>
      </div>
      <select
        name={"choices[#{@item.key}]"}
        aria-label={"What to do with #{@item.imported.name}"}
        class={["select w-36 sm:w-44", @item.existing && "select-warning"]}
      >
        <option :for={{label, action} <- @options} value={action} selected={action == @choice}>
          {label}
        </option>
      </select>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :slots, :list, required: true
  attr :chosen, :list, required: true
  attr :event, :string, required: true
  attr :key, :string, required: true

  defp slot_chips(assigns) do
    ~H"""
    <.chip_group id={"slots-#{@id}"} label="Slots">
      <.chip
        :for={slot <- @slots}
        id={"slot-#{@id}-#{slot.id}"}
        pressed={slot.id in @chosen}
        phx-click={@event}
        phx-value-key={@key}
        phx-value-slot={slot.id}
      >
        {slot.name}
      </.chip>
    </.chip_group>
    """
  end

  attr :summary, :map, required: true

  defp done_step(assigns) do
    ~H"""
    <div
      id="import-summary"
      class="space-y-4 rounded-box border border-success/40 bg-base-100 p-4 sm:p-5"
    >
      <h2 class="flex items-center gap-2 text-xl font-semibold">
        <.icon name="hero-check-circle" class="size-6 text-success" /> Imported
      </h2>
      <ul class="space-y-1">
        <li>Recipes: {summary_line(@summary.recipes)}</li>
        <li>Meals: {summary_line(@summary.meals)}</li>
      </ul>
      <div class="flex flex-wrap gap-2">
        <.button navigate={~p"/recipes"}>Recipes</.button>
        <.button navigate={~p"/meals"}>Meals</.button>
        <button type="button" class="btn btn-ghost" phx-click="start_over">Import more</button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if Households.owner?(socket.assigns.current_scope) do
      limits = Transfer.limits()

      {:ok,
       socket
       |> assign(page_title: "Import", step: :upload, import: nil, choices: %{}, summary: nil)
       |> assign(slots: [], bulk_slots: [])
       |> allow_upload(:files,
         accept: ~w(.zip .cook .menu),
         max_entries: limits.files,
         max_file_size: limits.upload_bytes
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only the household's owner can import.")
       |> push_navigate(to: ~p"/household")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :files, ref)}

  def handle_event("read", _params, socket) do
    uploads =
      consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    import = Transfer.plan(socket.assigns.current_scope, Transfer.read(uploads))
    choices = Map.new(import.recipes ++ import.meals, &{&1.key, &1.action})
    slots = Households.list_meal_slots(socket.assigns.current_scope)

    {:noreply,
     assign(socket,
       step: :preview,
       import: import,
       choices: choices,
       slots: slots,
       bulk_slots: []
     )}
  end

  def handle_event("choose", %{"choices" => chosen}, socket) do
    {:noreply, assign(socket, choices: merge_choices(socket.assigns, chosen))}
  end

  def handle_event("toggle_slot", %{"key" => key, "slot" => slot_id}, socket) do
    %{import: import, slots: slots} = socket.assigns

    case {Enum.find(import.meals, &(&1.key == key)), slot_id in Enum.map(slots, & &1.id)} do
      {%ImportItem{} = item, true} ->
        {:noreply,
         assign(socket,
           import: Transfer.choose_slots(import, key, toggle(item.slot_ids, slot_id))
         )}

      _unknown ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_bulk_slot", %{"slot" => slot_id}, socket) do
    if slot_id in Enum.map(socket.assigns.slots, & &1.id),
      do: {:noreply, assign(socket, bulk_slots: toggle(socket.assigns.bulk_slots, slot_id))},
      else: {:noreply, socket}
  end

  def handle_event("apply_bulk_slots", _params, socket) do
    %{import: import, choices: choices, bulk_slots: bulk} = socket.assigns

    import =
      Enum.reduce(untagged(import, choices), import, &Transfer.choose_slots(&2, &1.key, bulk))

    {:noreply, assign(socket, import: import, bulk_slots: [])}
  end

  def handle_event("apply", params, socket) do
    choices = merge_choices(socket.assigns, Map.get(params, "choices", %{}))

    case Transfer.apply(socket.assigns.current_scope, socket.assigns.import, choices) do
      {:ok, summary} ->
        {:noreply, assign(socket, step: :done, summary: summary, import: nil, choices: %{})}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, "That's a lot of imports. Please try again in an hour.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the household's owner can import.")}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Nothing was imported: something changed meanwhile. Start over to see the latest."
         )}
    end
  end

  def handle_event("start_over", _params, socket) do
    {:noreply,
     assign(socket, step: :upload, import: nil, choices: %{}, summary: nil, bulk_slots: [])}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Only actions offered for an item are taken from the form.
  defp merge_choices(%{import: import, choices: choices}, chosen) do
    for item <- import.recipes ++ import.meals, into: choices do
      action = Enum.find(ImportItem.actions(item), &(Atom.to_string(&1) == chosen[item.key]))
      {item.key, action || choices[item.key]}
    end
  end

  defp toggle(ids, id), do: if(id in ids, do: List.delete(ids, id), else: ids ++ [id])

  # Tags only matter for meals being added, kept or replacing ours.
  defp tags?(action), do: action in [:add, :keep_both, :replace]

  defp untagged(import, choices),
    do: Enum.filter(import.meals, &(tags?(choices[&1.key]) and &1.slot_ids == []))

  defp counts(import) do
    items = import.recipes ++ import.meals
    matches = Enum.count(items, & &1.existing)

    "#{plural(length(import.recipes), "recipe")} and #{plural(length(import.meals), "meal")}: " <>
      "#{length(items) - matches} new, #{matches} already here."
  end

  defp references(%ImportItem{references: []}, _import, _choices), do: "No recipes"

  defp references(%ImportItem{references: references}, import, choices) do
    Enum.map_join(references, ", ", fn
      {:imported, key} ->
        item = Enum.find(import.recipes, &(&1.key == key))

        # Where the meal's link will point after the import.
        case choices[key] do
          :leave_out -> "#{item.imported.name} (left out)"
          :skip -> "#{item.existing.name} (ours)"
          :keep_both -> "#{item.imported.name} (copy)"
          _added_or_replaced -> item.imported.name
        end

      {:existing, recipe} ->
        "#{recipe.name} (ours)"

      {:missing, label} ->
        "#{label} (not found)"
    end)
  end

  defp summary_line(counts) do
    [
      {counts.added, "added"},
      {counts.replaced, "replaced"},
      {counts.skipped, "skipped"},
      {counts.left_out, "left out"}
    ]
    |> Enum.reject(fn {count, _label} -> count == 0 end)
    |> Enum.map_join(", ", fn {count, label} -> "#{count} #{label}" end)
    |> case do
      "" -> "none"
      line -> line
    end
  end

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(count, noun), do: "#{count} #{noun}s"

  defp upload_error(:too_large), do: "too large (10 MB at most)"
  defp upload_error(:not_accepted), do: "not a .zip, .cook or .menu file"
  defp upload_error(:too_many_files), do: "too many files (200 at most)"
  defp upload_error(error), do: to_string(error)
end
