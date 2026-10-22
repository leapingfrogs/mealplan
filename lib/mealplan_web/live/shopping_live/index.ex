defmodule MealplanWeb.ShoppingLive.Index do
  @moduledoc """
  The household's shopping list (iteration 4 design, "Screens"): what the
  planned meals need, ticked off live by every member, with manual items and
  staples. Any member can use it.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Planning
  alias Mealplan.Shopping
  alias Mealplan.Shopping.Item
  alias Mealplan.Shopping.Quantity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="shopping" wide>
      <.page_header>
        Shopping
        <:meta>{counts(@view)}</:meta>
        <:actions>
          <button
            type="button"
            id="change-range"
            class="btn btn-outline border-base-300"
            phx-click="toggle_range"
            aria-expanded={to_string(@range_form != nil)}
            aria-label={"Change the days, now #{range_label(@view.list, @today)}"}
          >
            <.icon name="hero-calendar-days" class="size-4" /> {range_label(@view.list, @today)}
          </button>
          <.link navigate={~p"/shopping/staples"} id="manage-staples" class="btn btn-ghost">
            <.icon name="hero-bookmark" class="size-4" />
            <span class="max-sm:sr-only">Staples</span>
          </.link>
        </:actions>
        <:menu>
          <button type="button" id="copy-list" phx-hook=".CopyText" data-text={copy_text(@view)}>
            <.icon name="hero-clipboard-document" class="size-4" />
            <span data-label>Copy as text</span>
          </button>
        </:menu>
        <:menu>
          <button
            type="button"
            id="start-new"
            phx-click={JS.push("start_new") |> JS.remove_attribute("open", to: "#page-header-menu")}
          >
            <.icon name="hero-arrow-path" class="size-4" /> Start a new list
          </button>
        </:menu>
      </.page_header>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyText">
        export default {
          mounted() {
            this.el.addEventListener("click", async () => {
              const label = this.el.querySelector("[data-label]")
              try {
                await navigator.clipboard.writeText(this.el.dataset.text)
                label.textContent = "Copied"
              } catch (_error) {
                label.textContent = "Couldn't copy"
              }
              setTimeout(() => { label.textContent = "Copy as text" }, 1500)
            })
          }
        }
      </script>

      <.form
        :if={@range_form}
        for={@range_form}
        id="range-form"
        phx-submit="save_range"
        class="max-w-form space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
      >
        <div class="flex flex-wrap gap-2">
          <button type="button" class="btn" phx-click="range_preset" phx-value-preset="this">
            This week
          </button>
          <button type="button" class="btn" phx-click="range_preset" phx-value-preset="next">
            Next week
          </button>
        </div>
        <div class="grid grid-cols-2 gap-2">
          <.input field={@range_form[:starts_on]} type="date" label="From" />
          <.input field={@range_form[:ends_on]} type="date" label="To" />
        </div>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn btn-ghost" phx-click="toggle_range">Cancel</button>
          <button type="submit" id="save-range" class="btn btn-primary">Show</button>
        </div>
      </.form>

      <.confirm_panel
        :if={@confirm_new}
        id="start-new-panel"
        title="Start a new list?"
        confirm="Start a new list"
        confirm_id="confirm-start-new"
        on_confirm="confirm_new"
        on_cancel="cancel_new"
      >
        It starts from today. Ticks and items already bought are cleared; items you added
        and haven't bought stay.
      </.confirm_panel>

      <.add_form
        for={@item_form}
        id="item-form"
        field={@item_form[:text]}
        label="Add an item"
        placeholder="Add an item, e.g. Kitchen roll"
        phx-change="edit_item"
        phx-submit="add_item"
      />

      <%!-- The list, with added items, ticked and staples beside it from 1024 px. --%>
      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start">
        <section id="to-buy" aria-label="To buy">
          <ul
            :if={@view.to_buy != []}
            class="divide-y divide-base-300 overflow-hidden rounded-box border border-base-300 bg-base-100 min-[85rem]:columns-2 min-[85rem]:gap-0 min-[85rem]:[column-rule:1px_solid_var(--color-base-300)]"
          >
            <li :for={entry <- @view.to_buy} id={line_id(entry.line.key)} class="break-inside-avoid">
              <.line_row
                line={entry.line}
                more={entry.more}
                ticked={false}
                open={MapSet.member?(@open, entry.line.key)}
              />
            </li>
          </ul>
          <.empty_state :if={@view.to_buy == [] and unticked(@view.items) == []} id="nothing-to-buy">
            <%= if @view.ticked == [] do %>
              Nothing planned needs buying for these days.
            <% else %>
              All done.
            <% end %>
            <:action :if={@view.ticked == []}>
              <.button navigate={~p"/plan"}>Plan some meals</.button>
            </:action>
          </.empty_state>
        </section>

        <aside class="space-y-4 lg:sticky lg:top-6">
          <section :if={unticked(@view.items) != []} id="added" class="space-y-2">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Added by you
            </h2>
            <ul class="divide-y divide-base-300 overflow-hidden rounded-box border border-base-300 bg-base-100">
              <li :for={item <- unticked(@view.items)} id={"item-#{item.id}"}>
                <.item_row item={item} />
              </li>
            </ul>
          </section>

          <.collapsible
            :if={@view.ticked != [] or ticked(@view.items) != []}
            id="ticked"
            title="Ticked"
            count={length(@view.ticked) + length(ticked(@view.items))}
            open={ticked_open?(@view, @collapsed)}
            on_toggle="toggle_group"
            value="ticked"
          >
            <ul class="divide-y divide-base-300">
              <li :for={entry <- @view.ticked} id={line_id(entry.line.key)}>
                <.line_row line={entry.line} more={nil} ticked={true} open={false} />
              </li>
              <li :for={item <- ticked(@view.items)} id={"item-#{item.id}"}>
                <.item_row item={item} />
              </li>
            </ul>
          </.collapsible>

          <.collapsible
            :if={@view.staples != []}
            id="staples"
            title="Staples, not listed"
            count={length(@view.staples)}
            open={not MapSet.member?(@collapsed, "staples")}
            on_toggle="toggle_group"
            value="staples"
          >
            <ul class="divide-y divide-base-300">
              <li
                :for={line <- @view.staples}
                id={"staple-" <> line_id(line.key)}
                class="flex items-center justify-between gap-3 px-4 py-2"
              >
                <span class="min-w-0">
                  <span class="block break-words">{line.name}</span>
                  <span class="text-sm text-base-content/70 tabular-nums">{line.amount}</span>
                </span>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm shrink-0"
                  phx-click="need_staple"
                  phx-value-name={line.name}
                >
                  <.icon name="hero-plus" class="size-4" /> Need some
                </button>
              </li>
            </ul>
          </.collapsible>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  attr :line, :any, required: true
  attr :more, :any, required: true
  attr :ticked, :boolean, required: true
  attr :open, :boolean, required: true

  defp line_row(assigns) do
    ~H"""
    <div class="flex items-center">
      <button
        type="button"
        class="flex min-h-14 min-w-0 flex-1 items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-base-200/60"
        phx-click={if @ticked, do: "untick", else: "tick"}
        phx-value-key={@line.key}
        aria-pressed={to_string(@ticked)}
      >
        <span class={[
          "flex size-6 shrink-0 items-center justify-center rounded-md border-2 transition-colors",
          if(@ticked, do: "border-primary bg-primary text-primary-content", else: "border-base-300")
        ]}>
          <.icon :if={@ticked} name="hero-check" class="size-4" />
        </span>
        <span class="min-w-0 flex-1 break-words">
          <span class={["block", @ticked && "text-base-content/50 line-through"]}>
            {@line.name}
            <span :if={@line.optional} class="badge badge-ghost badge-sm align-middle">optional</span>
          </span>
          <span :if={@more} class="block text-sm text-warning">
            {Quantity.to_string(@more)} more since ticked
          </span>
        </span>
        <span class={[
          "max-w-[45%] shrink-0 text-right tabular-nums",
          if(@ticked, do: "text-base-content/50", else: "text-base-content/80")
        ]}>
          {@line.amount}
        </span>
      </button>
      <button
        :if={not @ticked}
        type="button"
        class="btn btn-ghost btn-square mr-1 shrink-0"
        phx-click="toggle_line"
        phx-value-key={@line.key}
        aria-expanded={to_string(@open)}
        aria-label={"Where #{@line.name} comes from"}
      >
        <.icon
          name="hero-chevron-down"
          class={["size-4 transition-transform", @open && "rotate-180"]}
        />
      </button>
    </div>
    <div :if={@open} class="space-y-2 px-4 pb-3 pl-13 text-sm">
      <ul class="space-y-0.5 text-base-content/70">
        <li :for={source <- @line.sources}>{source_label(source)}</li>
      </ul>
      <button
        type="button"
        class="btn btn-ghost btn-sm"
        phx-click="make_staple"
        phx-value-name={@line.name}
      >
        <.icon name="hero-bookmark" class="size-4" /> Always have this
      </button>
    </div>
    """
  end

  attr :item, :any, required: true

  defp item_row(assigns) do
    ~H"""
    <div class="flex items-center">
      <button
        type="button"
        class="flex min-h-14 min-w-0 flex-1 items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-base-200/60"
        phx-click="tick_item"
        phx-value-id={@item.id}
        phx-value-ticked={to_string(is_nil(@item.ticked_at))}
        aria-pressed={to_string(not is_nil(@item.ticked_at))}
      >
        <span class={[
          "flex size-6 shrink-0 items-center justify-center rounded-md border-2 transition-colors",
          if(@item.ticked_at,
            do: "border-primary bg-primary text-primary-content",
            else: "border-base-300"
          )
        ]}>
          <.icon :if={@item.ticked_at} name="hero-check" class="size-4" />
        </span>
        <span class={["min-w-0 break-words", @item.ticked_at && "text-base-content/50 line-through"]}>
          {@item.text}
        </span>
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-square mr-1 shrink-0"
        phx-click="remove_item"
        phx-value-id={@item.id}
        aria-label={"Remove #{@item.text}"}
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Shopping",
       open: MapSet.new(),
       collapsed: MapSet.new(["staples"]),
       range_form: nil,
       confirm_new: false,
       item_form: to_form(Shopping.change_item())
     )
     |> load()}
  end

  @impl true
  def handle_event("tick", %{"key" => key}, socket) do
    _ = Shopping.tick(socket.assigns.current_scope, key)
    {:noreply, socket |> update(:open, &MapSet.delete(&1, key)) |> load()}
  end

  def handle_event("untick", %{"key" => key}, socket) do
    {:ok, _list} = Shopping.untick(socket.assigns.current_scope, key)
    {:noreply, load(socket)}
  end

  def handle_event("toggle_line", %{"key" => key}, socket),
    do: {:noreply, update(socket, :open, &toggle(&1, key))}

  def handle_event("toggle_group", %{"group" => group}, socket)
      when group in ~w(ticked staples) do
    # "ticked" starts open while short, so toggling flips what it shows now.
    collapsed =
      case group do
        "ticked" ->
          if ticked_open?(socket.assigns.view, socket.assigns.collapsed),
            do: socket.assigns.collapsed |> MapSet.put("ticked") |> MapSet.delete("ticked-open"),
            else: socket.assigns.collapsed |> MapSet.delete("ticked") |> MapSet.put("ticked-open")

        "staples" ->
          toggle(socket.assigns.collapsed, "staples")
      end

    {:noreply, assign(socket, collapsed: collapsed)}
  end

  # Keeps the server's copy of the field in step, so clearing it after Add
  # reaches the browser: LiveView leaves a focused input alone unless its
  # value changes.
  def handle_event("edit_item", %{"item" => params}, socket),
    do: {:noreply, assign(socket, item_form: to_form(Shopping.change_item(%Item{}, params)))}

  def handle_event("add_item", %{"item" => params}, socket) do
    case Shopping.add_item(socket.assigns.current_scope, params) do
      {:ok, _item} ->
        {:noreply, socket |> assign(item_form: to_form(Shopping.change_item())) |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, item_form: to_form(changeset))}
    end
  end

  def handle_event("tick_item", %{"id" => id, "ticked" => ticked}, socket) do
    _ = Shopping.tick_item(socket.assigns.current_scope, id, ticked == "true")
    {:noreply, load(socket)}
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    _ = Shopping.remove_item(socket.assigns.current_scope, id)
    {:noreply, load(socket)}
  end

  def handle_event("make_staple", %{"name" => name}, socket) do
    socket =
      case Shopping.add_staple(socket.assigns.current_scope, %{name: name}) do
        {:ok, staple} -> put_flash(socket, :info, "#{staple.name} is a staple now.")
        {:error, _changeset} -> put_flash(socket, :error, "Couldn't make #{name} a staple.")
      end

    {:noreply, load(socket)}
  end

  def handle_event("need_staple", %{"name" => name}, socket) do
    _ = Shopping.add_item(socket.assigns.current_scope, %{text: name})
    {:noreply, load(socket)}
  end

  def handle_event("toggle_range", _params, socket) do
    form =
      if socket.assigns.range_form,
        do: nil,
        else: to_form(Shopping.change_range(socket.assigns.view.list))

    {:noreply, assign(socket, range_form: form)}
  end

  def handle_event("range_preset", %{"preset" => preset}, socket) do
    scope = socket.assigns.current_scope
    monday = Planning.current_week(scope)

    {starts_on, ends_on} =
      case preset do
        "next" -> {Date.add(monday, 7), Date.add(monday, 13)}
        _this -> {socket.assigns.today, Date.add(monday, 6)}
      end

    save_range(socket, %{starts_on: starts_on, ends_on: ends_on})
  end

  def handle_event("save_range", %{"shopping_list" => params}, socket),
    do: save_range(socket, params)

  def handle_event("start_new", _params, socket),
    do: {:noreply, assign(socket, confirm_new: true)}

  def handle_event("cancel_new", _params, socket),
    do: {:noreply, assign(socket, confirm_new: false)}

  def handle_event("confirm_new", _params, socket) do
    {:ok, _list} = Shopping.start_new(socket.assigns.current_scope)

    {:noreply,
     socket |> assign(confirm_new: false, range_form: nil, open: MapSet.new()) |> load()}
  end

  # The list follows the plan, recipes, meals and other members' ticks.
  @impl true
  def handle_info({:shopping_changed, _household_id}, socket), do: {:noreply, load(socket)}
  def handle_info({:plan_changed, _monday}, socket), do: {:noreply, load(socket)}
  def handle_info({:recipe_changed, _id}, socket), do: {:noreply, load(socket)}
  def handle_info({:meal_changed, _id}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp save_range(socket, attrs) do
    case Shopping.set_range(socket.assigns.current_scope, attrs) do
      {:ok, _list} -> {:noreply, socket |> assign(range_form: nil) |> load()}
      {:error, changeset} -> {:noreply, assign(socket, range_form: to_form(changeset))}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    assign(socket, view: Shopping.view(scope), today: Planning.today(scope))
  end

  defp toggle(set, value),
    do:
      if(MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value))

  # Ticked starts open while it's short (a few), collapsed once it grows,
  # unless someone chose otherwise.
  defp ticked_open?(view, collapsed) do
    cond do
      MapSet.member?(collapsed, "ticked") -> false
      MapSet.member?(collapsed, "ticked-open") -> true
      true -> length(view.ticked) + length(ticked(view.items)) <= 3
    end
  end

  defp unticked(items), do: Enum.filter(items, &is_nil(&1.ticked_at))

  defp counts(view) do
    to_buy = length(view.to_buy) + length(unticked(view.items))
    ticked = length(view.ticked) + length(ticked(view.items))
    "#{to_buy} to buy · #{ticked} ticked"
  end

  defp ticked(items), do: Enum.reject(items, &is_nil(&1.ticked_at))

  @doc "The DOM id for an ingredient line (keys can hold any characters)."
  def line_id(key), do: "line-" <> Base.url_encode64(key, padding: false)

  defp range_label(list, today) do
    from = if list.starts_on == today, do: "Today", else: day(list.starts_on)
    if list.starts_on == list.ends_on, do: from, else: "#{from} – #{day(list.ends_on)}"
  end

  defp day(date), do: Calendar.strftime(date, "%a %-d %b")

  defp source_label(%{planned_meal: planned_meal, recipe: recipe, amount: amount}) do
    "#{recipe.name} · #{Calendar.strftime(planned_meal.date, "%a")} " <>
      "#{String.downcase(planned_meal.meal_slot.name)} · #{amount}"
  end

  defp copy_text(view) do
    lines = for %{line: line} <- view.to_buy, do: "#{line.name}: #{line.amount}"
    Enum.join(lines ++ Enum.map(unticked(view.items), & &1.text), "\n")
  end
end
