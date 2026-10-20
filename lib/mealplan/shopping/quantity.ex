defmodule Mealplan.Shopping.Quantity do
  @moduledoc """
  An amount of one ingredient on the shopping list, merged from any number
  of recipe rows (iteration 4 design, "Merging and units"). Pure.

    * `mass` and `volume` - metric amounts, in grams and millilitres
    * `units` - other units (tsp, cup, oz, or ones we don't know), each kept
      apart: `%{canonical => %{amount: Decimal, one: spelling, many: spelling}}`,
      with the unit as written for one and for several, for display
    * `count` - a number of things, without a unit
    * `texts` - quantities written as text ("a handful"), once each
    * `some` - an ingredient without a quantity
  """
  @type t :: %__MODULE__{
          mass: Decimal.t() | nil,
          volume: Decimal.t() | nil,
          units: %{String.t() => %{amount: Decimal.t(), one: String.t(), many: String.t()}},
          count: Decimal.t() | nil,
          texts: [String.t()],
          some: boolean()
        }

  defstruct mass: nil, volume: nil, units: %{}, count: nil, texts: [], some: false

  @metric %{
    "mg" => {:mass, "0.001"},
    "g" => {:mass, "1"},
    "kg" => {:mass, "1000"},
    "ml" => {:volume, "1"},
    "cl" => {:volume, "10"},
    "dl" => {:volume, "100"},
    "l" => {:volume, "1000"}
  }

  @doc """
  The quantity of one ingredient row (a `Mealplan.Recipes.RecipeIngredient`
  or a map with its fields), multiplied by `scale`.
  """
  def new(row, scale \\ Decimal.new(1))

  def new(%{quantity: %Decimal{} = quantity} = row, scale) do
    amount = Decimal.mult(quantity, scale)

    case {Map.get(@metric, row.canonical_unit), row.canonical_unit, row.dimension} do
      {{dimension, factor}, _unit, _dimension} ->
        Map.put(%__MODULE__{}, dimension, Decimal.mult(amount, factor))

      {nil, nil, _dimension} ->
        %__MODULE__{count: amount}

      {nil, unit, _dimension} ->
        written = row.unit || unit
        spelling = if Decimal.eq?(quantity, 1), do: :one, else: :many
        %__MODULE__{units: %{unit => Map.put(%{amount: amount}, spelling, written)}}
    end
  end

  def new(%{quantity_text: text}, _scale) when is_binary(text) do
    case String.trim(text) do
      "" -> %__MODULE__{some: true}
      text -> %__MODULE__{texts: [text]}
    end
  end

  def new(_row, _scale), do: %__MODULE__{some: true}

  @doc "Adds two quantities."
  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      mass: add_number(a.mass, b.mass),
      volume: add_number(a.volume, b.volume),
      units: Map.merge(a.units, b.units, fn _unit, x, y -> add_unit(x, y) end),
      count: add_number(a.count, b.count),
      texts: Enum.sort(Enum.uniq(a.texts ++ b.texts)),
      some: a.some or b.some
    }
  end

  @doc "Adds up a list of quantities."
  def sum(quantities), do: Enum.reduce(quantities, %__MODULE__{}, &add(&2, &1))

  defp add_number(nil, b), do: b
  defp add_number(a, nil), do: a
  defp add_number(a, b), do: Decimal.add(a, b)

  defp add_unit(x, y) do
    %{
      amount: Decimal.add(x.amount, y.amount),
      one: Map.get(x, :one) || Map.get(y, :one),
      many: Map.get(x, :many) || Map.get(y, :many)
    }
  end

  @doc """
  The quantity for the list: its parts joined with " + " (metric mass, metric
  volume, other units, a count, then texts), or "some" when there's no
  amount at all. Metric amounts take the larger unit from 1000 up, counts
  round up to a whole number, and everything else shows at most two
  decimal places.

      iex> alias Mealplan.Shopping.Quantity
      iex> a = Quantity.new(%{quantity: Decimal.new(750), unit: "g", canonical_unit: "g", dimension: :mass})
      iex> b = Quantity.new(%{quantity: Decimal.new("0.5"), unit: "kg", canonical_unit: "kg", dimension: :mass})
      iex> Quantity.to_string(Quantity.add(a, b))
      "1.25 kg"
  """
  def to_string(%__MODULE__{} = quantity) do
    parts =
      Enum.reject(
        [metric(quantity.mass, "g", "kg", "mg"), metric(quantity.volume, "ml", "l", nil)] ++
          units(quantity.units) ++ [count(quantity.count) | quantity.texts],
        &is_nil/1
      )

    case parts do
      [] -> "some"
      parts -> Enum.join(parts, " + ")
    end
  end

  @doc "True when the quantity has no amount of any kind."
  def empty?(%__MODULE__{} = quantity), do: quantity == %__MODULE__{}

  defp metric(nil, _base, _large, _small), do: nil

  defp metric(amount, base, large, small) do
    cond do
      Decimal.compare(amount, 1000) != :lt ->
        "#{number(Decimal.div(amount, 1000))} #{large}"

      small && Decimal.compare(amount, 1) == :lt ->
        "#{number(Decimal.mult(amount, 1000))} #{small}"

      true ->
        "#{number(amount)} #{base}"
    end
  end

  defp units(units) do
    units
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {unit, %{amount: amount} = spellings} ->
      shown = number(amount)

      written =
        if shown == "1",
          do: Map.get(spellings, :one) || Map.get(spellings, :many) || unit,
          else: Map.get(spellings, :many) || unit

      "#{shown} #{written}"
    end)
  end

  defp count(nil), do: nil
  defp count(amount), do: amount |> Decimal.round(0, :ceiling) |> number()

  defp number(amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
