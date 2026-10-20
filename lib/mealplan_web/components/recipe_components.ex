defmodule MealplanWeb.RecipeComponents do
  @moduledoc """
  Renders parsed Cooklang (`Mealplan.Cooklang.Recipe`): the ingredient list,
  the method with ingredients, cookware and timers highlighted, and parse
  warnings. Used by the recipe page and the editor's preview.
  """
  use Phoenix.Component

  import MealplanWeb.CoreComponents, only: [icon: 1]

  alias Mealplan.Cooklang
  alias Mealplan.Cooklang.Cookware
  alias Mealplan.Cooklang.Ingredient
  alias Mealplan.Cooklang.Note
  alias Mealplan.Cooklang.Step
  alias Mealplan.Cooklang.Text
  alias Mealplan.Cooklang.Timer

  @fractions [
    {"0.25", "¼"},
    {"0.33", "⅓"},
    {"0.5", "½"},
    {"0.67", "⅔"},
    {"0.75", "¾"}
  ]

  @doc """
  Formats a quantity for reading: whole numbers plainly, common fractions as
  ¼ ½ ¾ ⅓ ⅔, other numbers to two decimal places, text as written.

      iex> MealplanWeb.RecipeComponents.format_quantity(Decimal.new("1.5"))
      "1½"
      iex> MealplanWeb.RecipeComponents.format_quantity(Decimal.div(1, 3))
      "⅓"
      iex> MealplanWeb.RecipeComponents.format_quantity(Decimal.new("2.125"))
      "2.13"
  """
  def format_quantity(nil), do: nil
  def format_quantity(text) when is_binary(text), do: text

  def format_quantity(%Decimal{} = number) do
    rounded = Decimal.round(number, 2)
    whole = Decimal.round(rounded, 0, :down)
    part = Decimal.sub(rounded, whole)

    case Enum.find(@fractions, fn {decimal, _glyph} -> Decimal.eq?(part, decimal) end) do
      {_decimal, glyph} when whole.coef == 0 -> glyph
      {_decimal, glyph} -> Decimal.to_string(whole, :normal) <> glyph
      nil -> rounded |> Decimal.normalize() |> Decimal.to_string(:normal)
    end
  end

  @doc "A quantity and unit as one string (\"250 g\"), or nil when neither is given."
  def amount(quantity, unit) do
    case Enum.reject([format_quantity(quantity), unit], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  attr :id, :string, required: true
  attr :ingredients, :list, required: true, doc: "`Mealplan.Cooklang.Ingredient`s"
  attr :class, :any, default: nil

  @doc "The ingredients, in the order the method uses them."
  def ingredient_list(assigns) do
    ~H"""
    <ul id={@id} class={["divide-y divide-base-300", @class]}>
      <li :for={ingredient <- @ingredients} class="flex items-baseline justify-between gap-3 py-2">
        <span class="min-w-0">
          <span class="font-medium">{ingredient.name}</span><span
            :if={ingredient.note}
            class="text-base-content/60"
          >, {ingredient.note}</span>
          <span :if={ingredient.optional} class="badge badge-ghost badge-sm ml-1">optional</span>
        </span>
        <span class="shrink-0 tabular-nums text-base-content/70">
          {amount(ingredient.quantity, ingredient.unit) || "some"}
        </span>
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :recipe, Cooklang.Recipe, required: true

  @doc "The method: sections of numbered steps and notes."
  def method(assigns) do
    ~H"""
    <div id={@id} class="space-y-6">
      <section :for={section <- @recipe.sections} class="space-y-3">
        <h3 :if={section.name} class="font-semibold">{section.name}</h3>
        <ol class="space-y-4">
          <%= for {block, number} <- number_steps(section.blocks) do %>
            <%= case block do %>
              <% %Step{items: items} -> %>
                <li class="flex gap-3">
                  <span class="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-base-200 text-xs font-semibold tabular-nums">
                    {number}
                  </span>
                  <p class="leading-relaxed"><.step_item :for={item <- items} item={item} /></p>
                </li>
              <% %Note{text: text} -> %>
                <li class="border-l-2 border-base-300 pl-3 text-sm italic text-base-content/70">
                  {text}
                </li>
            <% end %>
          <% end %>
        </ol>
      </section>
    </div>
    """
  end

  # Steps are numbered within their section; notes aren't numbered.
  defp number_steps(blocks) do
    {numbered, _count} =
      Enum.map_reduce(blocks, 0, fn
        %Step{} = step, count -> {{step, count + 1}, count + 1}
        block, count -> {{block, nil}, count}
      end)

    numbered
  end

  attr :item, :any, required: true

  # Each template renders without surrounding whitespace, so text such as
  # the comma in "@salt, then" sits right against the highlighted name.
  defp step_item(%{item: %Text{value: value}} = assigns) do
    assigns = assign(assigns, :lines, value |> String.split("\n") |> Enum.with_index())
    ~H|<span :for={{line, index} <- @lines}><br :if={index > 0} />{line}</span>|
  end

  defp step_item(%{item: %Ingredient{}} = assigns) do
    assigns = assign(assigns, :amount, amount(assigns.item.quantity, assigns.item.unit))

    ~H|<span class="font-medium text-primary">{@item.name}</span><span
  :if={@amount}
  class="text-base-content/60"
> ({@amount})</span>|
  end

  defp step_item(%{item: %Cookware{}} = assigns) do
    ~H|<span class="font-medium underline decoration-base-content/30">{@item.name}</span>|
  end

  defp step_item(%{item: %Timer{}} = assigns) do
    assigns =
      assign(
        assigns,
        :label,
        amount(assigns.item.quantity, assigns.item.unit) || assigns.item.name
      )

    ~H|<span class="whitespace-nowrap rounded-md bg-base-200 px-1 font-medium"><.icon
  name="hero-clock"
  class="size-3.5 align-[-2px]"
/> {@label}</span>|
  end

  attr :id, :string, required: true
  attr :warnings, :list, required: true

  @doc "Parse warnings, which never stop a recipe being saved."
  def warnings(assigns) do
    ~H"""
    <ul :if={@warnings != []} id={@id} class="space-y-1 text-sm text-warning">
      <li :for={warning <- @warnings} class="flex gap-2">
        <.icon name="hero-exclamation-triangle" class="size-4 shrink-0 mt-0.5" />
        <span>
          <span :if={warning.line} class="font-medium">Line {warning.line}:</span>
          {warning.message}
        </span>
      </li>
    </ul>
    """
  end
end
