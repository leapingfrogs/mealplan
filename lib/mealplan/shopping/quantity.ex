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
  amount at all. Amounts round UP to what you can buy: metric amounts to a
  step (0.5 under 10, 5 under 100, 25 under 1000, then 50, in g or ml) and
  take the larger unit from 1000 up; measuring units (spoons, cups, ounces)
  to the nearest half; everything else (tins, cloves, counts) to a whole
  number.

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

  @doc """
  How much more `current` is than `before` (a quantity as ticked), as shown:
  each metric amount, unit and count that grew, by how much, and texts that
  are new. Nil when nothing grew. Amounts are compared as shown, so a count
  that rounds to the same number hasn't grown.
  """
  def more(%__MODULE__{} = current, %__MODULE__{} = before) do
    units =
      for {unit, %{amount: amount} = spellings} <- current.units,
          extra = grew(amount, get_in(before.units, [unit, :amount]), &round_unit(unit, &1)),
          into: %{},
          do: {unit, %{spellings | amount: extra}}

    more = %__MODULE__{
      mass: grew(current.mass, before.mass, &round_metric/1),
      volume: grew(current.volume, before.volume, &round_metric/1),
      units: units,
      count: grew(current.count, before.count, &whole/1),
      texts: current.texts -- before.texts
    }

    if empty?(more), do: nil, else: more
  end

  defp grew(nil, _before, _round), do: nil

  defp grew(now, before, round) do
    extra = Decimal.sub(round.(now), round.(before || Decimal.new(0)))
    if Decimal.gt?(extra, 0), do: extra
  end

  @measures ["tsp", "tbsp", "cup", "fl oz", "pint", "oz", "lb"]

  # Metric amounts (g or ml) round up to a step that suits their size.
  defp round_metric(amount) do
    step =
      cond do
        Decimal.lt?(amount, 1) -> "0.05"
        Decimal.lt?(amount, 10) -> "0.5"
        Decimal.lt?(amount, 100) -> "5"
        Decimal.lt?(amount, 1000) -> "25"
        true -> "50"
      end

    ceil_to(amount, Decimal.new(step))
  end

  # Spoons, cups and ounces to the nearest half; tins, cloves and the rest whole.
  defp round_unit(unit, amount) when unit in @measures, do: ceil_to(amount, Decimal.new("0.5"))
  defp round_unit(_unit, amount), do: whole(amount)

  defp whole(amount), do: Decimal.round(amount, 0, :ceiling)

  defp ceil_to(amount, step), do: amount |> Decimal.div(step) |> whole() |> Decimal.mult(step)

  @doc "The quantity as a JSON-friendly map, for storing (amounts as strings)."
  def to_map(%__MODULE__{} = quantity) do
    %{
      "mass" => decimal_string(quantity.mass),
      "volume" => decimal_string(quantity.volume),
      "units" =>
        Map.new(quantity.units, fn {unit, %{amount: a}} -> {unit, decimal_string(a)} end),
      "count" => decimal_string(quantity.count),
      "texts" => quantity.texts,
      "some" => quantity.some
    }
  end

  @doc "Reads back `to_map/1`; anything unreadable is left out."
  def from_map(map) when is_map(map) do
    units =
      for {unit, amount} <- map["units"] || %{},
          is_binary(unit),
          amount = decimal(amount),
          into: %{},
          do: {unit, %{amount: amount}}

    %__MODULE__{
      mass: decimal(map["mass"]),
      volume: decimal(map["volume"]),
      units: units,
      count: decimal(map["count"]),
      texts: Enum.filter(List.wrap(map["texts"]), &is_binary/1),
      some: map["some"] == true
    }
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(amount), do: Decimal.to_string(amount, :normal)

  defp decimal(text) when is_binary(text) do
    case Decimal.parse(text) do
      {amount, ""} -> amount
      _invalid -> nil
    end
  end

  defp decimal(_none), do: nil

  @doc "True when the quantity has no amount of any kind."
  def empty?(%__MODULE__{} = quantity), do: quantity == %__MODULE__{}

  defp metric(nil, _base, _large, _small), do: nil

  defp metric(amount, base, large, small) do
    amount = round_metric(amount)

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
      shown = number(round_unit(unit, amount))

      written =
        if shown == "1",
          do: Map.get(spellings, :one) || Map.get(spellings, :many) || unit,
          else: Map.get(spellings, :many) || unit

      "#{shown} #{written}"
    end)
  end

  defp count(nil), do: nil
  defp count(amount), do: amount |> whole() |> number()

  defp number(amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
