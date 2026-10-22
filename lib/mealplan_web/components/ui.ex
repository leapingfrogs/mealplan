defmodule MealplanWeb.UI do
  @moduledoc """
  Mealplan's shared page components (the UI kit in the iteration 5 design).
  Every page builds from these rather than drawing its own headers, rows,
  forms and panels, so they look and behave the same everywhere. Imported
  into all LiveViews and HTML modules alongside `MealplanWeb.CoreComponents`.

    * `page_header/1` - back link, title, meta line, actions and a menu
    * `section_card/1` - a titled card for a group of settings or content
    * `row_list/1` and `list_row/1` - bordered lists whose rows wrap long names
    * `add_form/1` - one field and an Add button
    * `confirm_panel/1` - "are you sure", with what will be affected
    * `empty_state/1` - what goes here and how to add it
    * `chip_group/1` and `chip/1` - pill toggles
    * `stepper/1` - minus, value, plus
    * `collapsible/1` - a group with a header that opens and closes it
    * `sheet/1` - a bottom sheet on phones, a dialog on wider screens
  """
  use Phoenix.Component
  use Gettext, backend: MealplanWeb.Gettext

  import MealplanWeb.CoreComponents

  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  The top of a page: an optional back link, the title (always full width,
  wrapping), a meta line, actions on their own row (beside the title from
  1024 px) and an overflow menu for rarely used actions.

      <.page_header back={~p"/recipes"} back_label="Recipes">
        {@recipe.name}
        <:meta>Serves 6</:meta>
        <:actions><.button navigate={...}>Edit</.button></:actions>
        <:menu><.link href={...}>Download .cook</.link></:menu>
      </.page_header>
  """
  attr :id, :string, default: "page-header"
  attr :back, :string, default: nil, doc: "path of the parent page"
  attr :back_label, :string, default: nil, doc: "the parent's name, never the item's"
  slot :inner_block, required: true, doc: "the title"
  slot :meta, doc: "a line under the title"
  slot :actions, doc: "buttons"
  slot :menu, doc: "menu items (links or buttons) behind a ⋯ button"

  def page_header(assigns) do
    ~H"""
    <header id={@id} class="space-y-3 pb-2">
      <.link
        :if={@back}
        navigate={@back}
        class="inline-flex min-h-8 items-center gap-1.5 text-sm font-medium text-base-content/70 hover:text-base-content"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {@back_label}
      </.link>
      <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between lg:gap-6">
        <div class="min-w-0 space-y-1 lg:flex-1">
          <h1 class="text-2xl font-bold leading-tight break-words lg:text-3xl">
            {render_slot(@inner_block)}
          </h1>
          <p :if={@meta != []} class="text-sm text-base-content/70">{render_slot(@meta)}</p>
        </div>
        <div
          :if={@actions != [] or @menu != []}
          class="flex flex-wrap items-center gap-2 lg:flex-none lg:justify-end"
        >
          {render_slot(@actions)}
          <details :if={@menu != []} id={"#{@id}-menu"} class="dropdown lg:dropdown-end">
            <summary class="btn btn-ghost btn-square list-none" aria-label={gettext("More actions")}>
              <.icon name="hero-ellipsis-horizontal" class="size-5" />
            </summary>
            <ul class="menu dropdown-content z-20 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 shadow-lg">
              <li :for={item <- @menu}>{render_slot(item)}</li>
            </ul>
          </details>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  A titled card for one group of content or settings. `danger` gives it a
  red border and heading (deleting a household).

      <.section_card id="meal-slots" title="Meal slots" help="The times of day you plan for.">
        ...
      </.section_card>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :help, :string, default: nil
  attr :danger, :boolean, default: false
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def section_card(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-title"}
      class={[
        "space-y-4 rounded-box border bg-base-100 p-4 sm:p-5",
        if(@danger, do: "border-error/40", else: "border-base-300"),
        @class
      ]}
    >
      <div class="space-y-1">
        <h2 id={"#{@id}-title"} class={["text-xl font-semibold", @danger && "text-error"]}>
          {@title}
        </h2>
        <p :if={@help} class="text-sm text-base-content/70">{@help}</p>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  A bordered list of `list_row/1`s. Rows draw their own dividers and round
  their own corners, so the list doesn't clip a `row_menu/1` opening below it.

      <.row_list id="recipes">
        <.list_row :for={r <- @recipes} id={"recipe-\#{r.id}"} navigate={~p"/recipes/\#{r}"}>
          {r.name}
          <:meta>Serves {r.servings}</:meta>
        </.list_row>
      </.row_list>
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def row_list(assigns) do
    ~H"""
    <ul
      id={@id}
      class={[
        "divide-y divide-base-300 rounded-box border border-base-300 bg-base-100",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </ul>
    """
  end

  @doc """
  One row: the title wraps to two lines (the full text as a tooltip), with
  an optional meta line, something leading (a tick box, a handle), a
  trailing value (an amount) and actions after the row's main target.

  With `navigate` the row is a link with a chevron; with `phx-click` it is a
  button (a tick row); otherwise it is plain.
  """
  attr :id, :string, required: true
  attr :navigate, :string, default: nil
  attr :title, :string, default: nil, doc: "full text for the tooltip when the title is clamped"
  attr :sortable_id, :string, default: nil, doc: "makes the row draggable in a Sortable list"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-value-key aria-pressed disabled)
  slot :inner_block, required: true, doc: "the title"
  slot :meta
  slot :lead
  slot :trailing
  slot :actions

  def list_row(assigns) do
    assigns = assign(assigns, :clickable?, assigns.rest[:"phx-click"] != nil)

    ~H"""
    <li
      id={@id}
      data-id={@sortable_id}
      draggable={@sortable_id && "true"}
      class={["group/row flex min-w-0 items-center", @class]}
    >
      <%= cond do %>
        <% @navigate -> %>
          <.link navigate={@navigate} class={row_main_class(@actions)} title={@title}>
            <.row_body {assigns} />
            <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/40" />
          </.link>
        <% @clickable? -> %>
          <button type="button" class={row_main_class(@actions)} title={@title} {@rest}>
            <.row_body {assigns} />
          </button>
        <% true -> %>
          <div class={row_main_class(@actions)} title={@title}>
            <.row_body {assigns} />
          </div>
      <% end %>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-1 pr-2">
        {render_slot(@actions)}
      </div>
    </li>
    """
  end

  defp row_main_class(actions) do
    [
      "flex min-h-14 min-w-0 flex-1 items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-base-200/60",
      "group-first/row:rounded-tl-box group-last/row:rounded-bl-box",
      actions == [] && "group-first/row:rounded-tr-box group-last/row:rounded-br-box"
    ]
  end

  defp row_body(assigns) do
    ~H"""
    <span :if={@lead != []} class="flex shrink-0 items-center">{render_slot(@lead)}</span>
    <span class="min-w-0 flex-1">
      <span class="line-clamp-2 break-words font-medium">{render_slot(@inner_block)}</span>
      <span :if={@meta != []} class="block text-sm text-base-content/70">{render_slot(@meta)}</span>
    </span>
    <span
      :if={@trailing != []}
      class="max-w-[45%] shrink-0 text-right text-base-content/70 tabular-nums"
    >
      {render_slot(@trailing)}
    </span>
    """
  end

  @doc """
  One field and an Add button in a form (new meal, slot, staple, invite,
  shopping item). The label is for screen readers unless `show_label`.

      <.add_form for={@item_form} id="item-form" field={@item_form[:text]}
        label="Add an item" placeholder="e.g. Kitchen roll" phx-submit="add_item" />
  """
  attr :for, :any, required: true
  attr :id, :string, required: true
  attr :field, FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil
  attr :button, :string, default: "Add"
  attr :show_label, :boolean, default: false
  attr :type, :string, default: "text"
  attr :rest, :global, include: ~w(phx-submit phx-change phx-target)

  def add_form(assigns) do
    ~H"""
    <.form for={@for} id={@id} class="space-y-1" {@rest}>
      <label for={@field.id} class={if(@show_label, do: "label", else: "sr-only")}>
        {@label}
      </label>
      <div class="flex items-start gap-2">
        <div class="min-w-0 flex-1">
          <.input field={@field} type={@type} placeholder={@placeholder} autocomplete="off" />
        </div>
        <.button class="btn-outline shrink-0" phx-disable-with={gettext("Adding…")}>
          <.icon name="hero-plus" class="size-4" /> {@button}
        </.button>
      </div>
    </.form>
    """
  end

  @doc """
  "Are you sure?" in place: what will happen, an optional list of what is
  affected, Cancel and the destructive action.

      <.confirm_panel id="delete-meal-panel" title="Delete this meal?"
        confirm="Delete meal" on_confirm="confirm_delete" on_cancel="cancel_delete">
        It's planned on these days; they will be removed from the plan:
        <:item>Thu 22 Oct, dinner</:item>
      </.confirm_panel>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :confirm, :string, required: true, doc: "the destructive button's label"

  attr :confirm_id, :string,
    default: nil,
    doc: "the destructive button's id (default: id-confirm)"

  attr :on_confirm, :any, default: nil, doc: "event or JS for the destructive button"

  attr :form, :string,
    default: nil,
    doc: "instead of on_confirm, the id of a form in :extra the button submits"

  attr :on_cancel, :any, required: true
  slot :inner_block, doc: "what will happen"
  slot :item, doc: "each thing affected"
  slot :extra, doc: "more controls, such as a type-to-confirm field"

  def confirm_panel(assigns) do
    ~H"""
    <section
      id={@id}
      role="alertdialog"
      aria-labelledby={"#{@id}-title"}
      class="space-y-3 rounded-box border border-error/40 bg-base-100 p-4 shadow-sm"
    >
      <h2 id={"#{@id}-title"} class="text-lg font-semibold">{@title}</h2>
      <div :if={@inner_block != []} class="text-sm">{render_slot(@inner_block)}</div>
      <ul :if={@item != []} class="list-disc space-y-1 pl-5 text-sm">
        <li :for={item <- @item}>{render_slot(item)}</li>
      </ul>
      {render_slot(@extra)}
      <div class="flex flex-wrap justify-end gap-2">
        <button type="button" class="btn btn-ghost" phx-click={@on_cancel}>
          {gettext("Cancel")}
        </button>
        <button
          type={if(@form, do: "submit", else: "button")}
          form={@form}
          id={@confirm_id || "#{@id}-confirm"}
          class="btn btn-error"
          phx-click={@on_confirm}
        >
          {@confirm}
        </button>
      </div>
    </section>
    """
  end

  @doc """
  A row's actions behind a ⋮ button, for rows with more than one action
  (a meal slot, a member). Items close the menu when they run JS
  (`close_menu/2`); a click outside closes it too.

      <.row_menu id={"slot-\#{slot.id}-menu"} label={"Actions for \#{slot.name}"}>
        <:item>
          <button type="button" phx-click={close_menu("edit_slot", "slot-\#{slot.id}-menu")}
            phx-value-id={slot.id}>Rename</button>
        </:item>
      </.row_menu>
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the button's name, naming the row"
  slot :item, required: true

  def row_menu(assigns) do
    ~H"""
    <details
      id={@id}
      class="dropdown dropdown-end"
      phx-click-away={JS.remove_attribute("open", to: "##{@id}")}
    >
      <summary class="btn btn-ghost btn-square list-none" aria-label={@label}>
        <.icon name="hero-ellipsis-vertical" class="size-5" />
      </summary>
      <ul class="menu dropdown-content z-20 mt-1 w-52 rounded-box border border-base-300 bg-base-100 p-1 shadow-lg [&>li>*]:min-h-11 lg:[&>li>*]:min-h-0">
        <li :for={item <- @item}>{render_slot(item)}</li>
      </ul>
    </details>
    """
  end

  @doc "Pushes `event` (with the element's phx-value-* attributes) and closes the menu."
  def close_menu(event, menu_id),
    do: event |> JS.push() |> JS.remove_attribute("open", to: "#" <> menu_id)

  @doc """
  The card the logged-out pages share (log in, the login link): a line
  about Mealplan above it, the card with its title, and a note below.

      <.auth_card title="Log in">
        <:intro>Plan the week's meals and shop for them together.</:intro>
        ...
        <:footer>No invitation? ...</:footer>
      </.auth_card>
  """
  attr :title, :string, required: true
  slot :intro
  slot :inner_block, required: true
  slot :footer

  def auth_card(assigns) do
    ~H"""
    <div class="mx-auto max-w-form space-y-6 sm:pt-8">
      <p
        :if={@intro != []}
        class="text-balance text-center font-display text-2xl font-bold leading-tight"
      >
        {render_slot(@intro)}
      </p>
      <section
        aria-labelledby="auth-title"
        class="space-y-4 rounded-2xl border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <h1 id="auth-title" class="font-display text-2xl font-semibold">{@title}</h1>
        {render_slot(@inner_block)}
      </section>
      <p :if={@footer != []} class="text-balance text-center text-sm text-base-content/70">
        {render_slot(@footer)}
      </p>
    </div>
    """
  end

  @doc """
  What goes here, and the action that adds it.

      <.empty_state id="no-recipes">
        No recipes yet.
        <:action><.button navigate={~p"/recipes/new"}>New recipe</.button></:action>
      </.empty_state>
  """
  attr :id, :string, required: true
  slot :inner_block, required: true
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex flex-col items-center gap-3 rounded-box border border-dashed border-base-300 px-4 py-8 text-center"
    >
      <p class="max-w-[40ch] text-base-content/70">{render_slot(@inner_block)}</p>
      <div :if={@action != []}>{render_slot(@action)}</div>
    </div>
    """
  end

  @doc """
  A labelled group of `chip/1` toggles (the slots a meal suits).

      <.chip_group label="Suits">
        <.chip :for={slot <- @slots} pressed={tagged?(slot)} phx-click="toggle_slot" phx-value-id={slot.id}>
          {slot.name}
        </.chip>
      </.chip_group>
  """
  attr :label, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def chip_group(assigns) do
    ~H"""
    <div id={@id} role="group" aria-label={@label} class="flex flex-wrap gap-2">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "A pill toggle; `pressed` shows a tick and sets `aria-pressed`."
  attr :pressed, :boolean, required: true
  attr :id, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-value-key phx-value-slot disabled)
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      aria-pressed={to_string(@pressed)}
      class={[
        "inline-flex min-h-10 items-center gap-1.5 rounded-full border px-4 text-sm font-medium transition-colors disabled:opacity-50",
        if(@pressed,
          do: "border-primary/40 bg-primary/10 text-primary",
          else: "border-base-300 bg-base-100 hover:bg-base-200"
        )
      ]}
      {@rest}
    >
      <.icon :if={@pressed} name="hero-check" class="size-4" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Minus, the value, plus. Each button sends `event` with `phx-value-delta`
  of -1 or 1; they disable at `min` and `max`.

      <.stepper id="add-servings" label="servings" value={@servings} event="adjust_servings" />
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "what is counted, for the buttons' names"
  attr :value, :integer, required: true
  attr :event, :string, required: true
  attr :min, :integer, default: 1
  attr :max, :integer, default: 100

  def stepper(assigns) do
    ~H"""
    <div id={@id} role="group" aria-label={@label} class="join">
      <button
        type="button"
        class="btn join-item btn-square"
        phx-click={@event}
        phx-value-delta="-1"
        disabled={@value <= @min}
        aria-label={gettext("Fewer %{label}", label: @label)}
      >
        <.icon name="hero-minus" class="size-4" />
      </button>
      <output
        aria-live="polite"
        class="join-item flex w-14 items-center justify-center border border-base-300 font-semibold tabular-nums"
      >
        {@value}
      </output>
      <button
        type="button"
        class="btn join-item btn-square"
        phx-click={@event}
        phx-value-delta="1"
        disabled={@value >= @max}
        aria-label={gettext("More %{label}", label: @label)}
      >
        <.icon name="hero-plus" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  A whole-number form field drawn as a `stepper/1`, with its value in a
  hidden input. The buttons send `event`; the LiveView works out the new
  value with `step_field/4` and puts it in the form's params.

      <.stepper_field field={@form[:usually_feeding]} label="Usually feeding"
        unit="people" event="adjust_feeding" max={50} />
  """
  attr :field, FormField, required: true
  attr :label, :string, required: true
  attr :unit, :string, required: true, doc: "what is counted, for the buttons' names"
  attr :event, :string, required: true
  attr :min, :integer, default: 1
  attr :max, :integer, default: 100
  attr :help, :string, default: nil

  def stepper_field(assigns) do
    assigns = assign(assigns, :value, field_integer(assigns.field, assigns.min))

    ~H"""
    <div class="space-y-1">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span id={"#{@field.id}-label"} class="font-medium">{@label}</span>
        <.stepper
          id={"#{@field.id}-stepper"}
          label={@unit}
          value={@value}
          event={@event}
          min={@min}
          max={@max}
        />
        <input type="hidden" id={@field.id} name={@field.name} value={@value} />
      </div>
      <p :if={@help} class="text-sm text-base-content/70">{@help}</p>
      <p :for={msg <- Enum.map(@field.errors, &translate_error/1)} class="text-sm text-error">
        {msg}
      </p>
    </div>
    """
  end

  @doc """
  The value a `stepper_field/1` moves to: its current value plus `delta` (the
  button's "-1" or "1"), kept within `min` and `max`.
  """
  def step_field(%FormField{} = field, delta, min, max) do
    value = field_integer(field, min)

    case Integer.parse(delta) do
      {step, ""} -> (value + step) |> max(min) |> min(max)
      _ -> value
    end
  end

  # The field holds a number from the data or a string from params.
  defp field_integer(field, default) do
    case field.value do
      n when is_integer(n) ->
        n

      text when is_binary(text) ->
        case Integer.parse(text) do
          {n, _rest} -> n
          :error -> default
        end

      _ ->
        default
    end
  end

  @doc """
  A group whose header opens and closes it. The body stays rendered (hidden
  when closed) so its elements keep their ids.

      <.collapsible id="ticked" title="Ticked" count={3} open={@ticked_open?}
        on_toggle="toggle_group" value="ticked">
        ...
      </.collapsible>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :count, :integer, default: nil
  attr :open, :boolean, required: true
  attr :on_toggle, :any, required: true, doc: "event or JS for the header"
  attr :value, :string, default: nil, doc: "sent as phx-value-group"
  slot :inner_block, required: true

  def collapsible(assigns) do
    ~H"""
    <section id={@id} class="overflow-hidden rounded-box border border-base-300 bg-base-100">
      <button
        type="button"
        class="flex min-h-12 w-full items-center justify-between gap-2 px-4 text-left font-semibold transition-colors hover:bg-base-200"
        phx-click={@on_toggle}
        phx-value-group={@value}
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-body"}
      >
        <span>
          {@title}
          <span :if={@count} class="font-normal text-base-content/60 tabular-nums">({@count})</span>
        </span>
        <.icon
          name="hero-chevron-down"
          class={["size-4 shrink-0 transition-transform", @open && "rotate-180"]}
        />
      </button>
      <div id={"#{@id}-body"} class={["border-t border-base-300", !@open && "hidden"]}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  A bottom sheet on phones and a centred dialog on wider screens, closed by
  the backdrop, the close button or Escape (all send `on_close`).

      <.sheet id="plan-sheet" title="Add to Dinner" on_close="close_sheet">...</.sheet>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_close, :any, required: true
  slot :inner_block, required: true

  def sheet(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4"
      phx-window-keydown={@on_close}
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/40" phx-click={@on_close} aria-hidden="true"></div>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        class="relative max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-base-100 p-4 pb-[max(1.5rem,env(safe-area-inset-bottom))] shadow-xl sm:max-w-md sm:rounded-2xl sm:pb-6"
        phx-mounted={
          JS.transition(
            {"ease-out duration-200", "translate-y-6 opacity-0", "translate-y-0 opacity-100"}
          )
        }
      >
        <div class="mx-auto mb-3 h-1 w-10 rounded-full bg-base-300 sm:hidden" aria-hidden="true">
        </div>
        <div class="mb-4 flex items-start justify-between gap-2">
          <h2 id={"#{@id}-title"} class="text-xl font-semibold leading-7">{@title}</h2>
          <button
            type="button"
            class="btn btn-ghost btn-square"
            phx-click={@on_close}
            aria-label={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
