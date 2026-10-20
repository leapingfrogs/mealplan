defmodule MealplanWeb.ShoppingLive.Index do
  @moduledoc """
  The household's shopping list (iteration 4 design, "Screens"): what the
  planned meals need, ticked off live by every member, with manual items and
  staples. Any member can use it.
  """
  use MealplanWeb, :live_view

  alias Mealplan.Planning
  alias Mealplan.Shopping
  alias Mealplan.Shopping.Quantity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Shopping
        <:subtitle>
          <button
            type="button"
            id="change-range"
            class="link link-hover"
            phx-click="toggle_range"
            aria-expanded={to_string(@range_form != nil)}
          >
            {range_label(@view.list, @today)}
          </button>
        </:subtitle>
        <:actions>
          <details id="shopping-menu" class="dropdown dropdown-end">
            <summary class="btn btn-ghost btn-sm btn-square" aria-label="More">
              <.icon name="hero-ellipsis-vertical" class="size-5" />
            </summary>
            <ul class="menu dropdown-content z-10 mt-1 w-52 rounded-box border border-base-300 bg-base-100 p-1 shadow">
              <li>
                <button
                  type="button"
                  id="copy-list"
                  phx-hook=".CopyText"
                  data-text={copy_text(@view)}
                >
                  <.icon name="hero-clipboard-document" class="size-4" />
                  <span data-label>Copy as text</span>
                </button>
              </li>
              <li>
                <.link navigate={~p"/shopping/staples"} id="manage-staples">
                  <.icon name="hero-archive-box" class="size-4" /> Staples
                </.link>
              </li>
              <li>
                <button
                  type="button"
                  id="start-new"
                  phx-click={
                    JS.push("start_new") |> JS.remove_attribute("open", to: "#shopping-menu")
                  }
                >
                  <.icon name="hero-arrow-path" class="size-4" /> Start a new list
                </button>
              </li>
            </ul>
          </details>
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
        </:actions>
      </.header>

      <.form
        :if={@range_form}
        for={@range_form}
        id="range-form"
        phx-submit="save_range"
        class="space-y-3 rounded-box border border-base-300 p-3"
      >
        <div class="flex flex-wrap gap-2">
          <button type="button" class="btn btn-sm" phx-click="range_preset" phx-value-preset="this">
            This week
          </button>
          <button type="button" class="btn btn-sm" phx-click="range_preset" phx-value-preset="next">
            Next week
          </button>
        </div>
        <div class="grid grid-cols-2 gap-2">
          <.input field={@range_form[:starts_on]} type="date" label="From" />
          <.input field={@range_form[:ends_on]} type="date" label="To" />
        </div>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn btn-sm btn-ghost" phx-click="toggle_range">Cancel</button>
          <button type="submit" id="save-range" class="btn btn-primary btn-sm">Show</button>
        </div>
      </.form>

      <div
        :if={@confirm_new}
        id="start-new-panel"
        role="alert"
        class="space-y-3 rounded-box border border-warning/50 bg-warning/10 p-4"
      >
        <p class="text-sm">
          Start a new list from today? Ticks and items already bought are cleared; items you added
          and haven't bought stay.
        </p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_new">Cancel</button>
          <button
            type="button"
            id="confirm-start-new"
            class="btn btn-sm btn-warning"
            phx-click="confirm_new"
          >
            Start a new list
          </button>
        </div>
      </div>

      <section id="to-buy" class="space-y-2">
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li :for={entry <- @view.to_buy} id={line_id(entry.line.key)}>
            <.line_row
              line={entry.line}
              more={entry.more}
              ticked={false}
              open={MapSet.member?(@open, entry.line.key)}
            />
          </li>
          <li :for={item <- unticked(@view.items)} id={"item-#{item.id}"}>
            <.item_row item={item} />
          </li>
          <li
            :if={@view.to_buy == [] and unticked(@view.items) == []}
            id="nothing-to-buy"
            class="px-4 py-8 text-center text-base-content/60"
          >
            <%= if @view.ticked == [] do %>
              Nothing planned needs buying for these days. <.link
                navigate={~p"/plan"}
                class="link"
              >Plan some meals</.link>, or add an item.
            <% else %>
              All done.
            <% end %>
          </li>
        </ul>

        <.form for={@item_form} id="item-form" phx-submit="add_item" class="flex items-start gap-2">
          <div class="flex-1">
            <.input
              field={@item_form[:text]}
              placeholder="Add an item, e.g. Kitchen roll"
              aria-label="Add an item"
              autocomplete="off"
            />
          </div>
          <.button aria-label="Add item"><.icon name="hero-plus" class="size-4" /></.button>
        </.form>
      </section>

      <section
        :if={@view.ticked != [] or ticked(@view.items) != []}
        id="ticked"
        class="overflow-hidden rounded-box border border-base-300"
      >
        <.group_toggle
          name="ticked"
          title="Ticked"
          count={length(@view.ticked) + length(ticked(@view.items))}
          open={ticked_open?(@view, @collapsed)}
        />
        <ul class={[
          "divide-y divide-base-300 border-t border-base-300",
          !ticked_open?(@view, @collapsed) && "hidden"
        ]}>
          <li :for={entry <- @view.ticked} id={line_id(entry.line.key)}>
            <.line_row line={entry.line} more={nil} ticked={true} open={false} />
          </li>
          <li :for={item <- ticked(@view.items)} id={"item-#{item.id}"}>
            <.item_row item={item} />
          </li>
        </ul>
      </section>

      <section
        :if={@view.staples != []}
        id="staples"
        class="overflow-hidden rounded-box border border-base-300"
      >
        <.group_toggle
          name="staples"
          title="Staples, not listed"
          count={length(@view.staples)}
          open={not MapSet.member?(@collapsed, "staples")}
        />
        <ul class={[
          "divide-y divide-base-300 border-t border-base-300",
          MapSet.member?(@collapsed, "staples") && "hidden"
        ]}>
          <li
            :for={line <- @view.staples}
            id={"staple-" <> line_id(line.key)}
            class="flex items-center justify-between gap-3 px-4 py-2"
          >
            <span class="min-w-0">
              <span class="block truncate">{line.name}</span>
              <span class="text-xs text-base-content/60">{line.amount}</span>
            </span>
            <button
              type="button"
              class="btn btn-ghost btn-xs shrink-0"
              phx-click="need_staple"
              phx-value-name={line.name}
            >
              <.icon name="hero-plus" class="size-3.5" /> Need some
            </button>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :line, :any, required: true
  attr :more, :any, required: true
  attr :ticked, :boolean, required: true
  attr :open, :boolean, required: true

  defp line_row(assigns) do
    ~H"""
    <div class="flex items-center gap-1 pr-2">
      <button
        type="button"
        class="flex min-h-12 flex-1 items-center gap-3 px-4 py-2 text-left transition-colors hover:bg-base-200/60"
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
        <span class="min-w-0">
          <span class={["block", @ticked && "text-base-content/50 line-through"]}>
            {@line.name}
            <span :if={@line.optional} class="badge badge-ghost badge-xs align-middle">optional</span>
          </span>
          <span class="text-sm text-base-content/60">
            {@line.amount}<span :if={@more} class="text-warning"> · {Quantity.to_string(@more)} more since ticked</span>
          </span>
        </span>
      </button>
      <button
        :if={not @ticked}
        type="button"
        class="btn btn-ghost btn-sm btn-square shrink-0"
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
        class="btn btn-ghost btn-xs"
        phx-click="make_staple"
        phx-value-name={@line.name}
      >
        <.icon name="hero-archive-box-arrow-down" class="size-3.5" /> Always have this
      </button>
    </div>
    """
  end

  attr :item, :any, required: true

  defp item_row(assigns) do
    ~H"""
    <div class="flex items-center gap-1 pr-2">
      <button
        type="button"
        class="flex min-h-12 flex-1 items-center gap-3 px-4 py-2 text-left transition-colors hover:bg-base-200/60"
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
        <span class={["min-w-0 truncate", @item.ticked_at && "text-base-content/50 line-through"]}>
          {@item.text}
        </span>
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-sm btn-square shrink-0"
        phx-click="remove_item"
        phx-value-id={@item.id}
        aria-label={"Remove #{@item.text}"}
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :title, :string, required: true
  attr :count, :integer, required: true
  attr :open, :boolean, required: true

  defp group_toggle(assigns) do
    ~H"""
    <button
      type="button"
      class="flex w-full items-center justify-between gap-2 px-4 py-2 text-left text-sm font-medium transition-colors hover:bg-base-200"
      phx-click="toggle_group"
      phx-value-group={@name}
      aria-expanded={to_string(@open)}
    >
      <span>{@title} <span class="font-normal text-base-content/50">({@count})</span></span>
      <.icon name="hero-chevron-down" class={["size-4 transition-transform", @open && "rotate-180"]} />
    </button>
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
