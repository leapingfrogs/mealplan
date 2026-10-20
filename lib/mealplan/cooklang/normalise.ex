defmodule Mealplan.Cooklang.Normalise do
  @moduledoc """
  Normalises ingredient names and units so the same ingredient written in
  different ways ("2 Tomatoes", "1 tomato") can be merged and scaled.

  Singularising is a small English heuristic, not a dictionary: it only has
  to map the forms recipes commonly use to the same key.
  """

  alias Mealplan.Cooklang.Ingredient

  @irregular %{
    "leaves" => "leaf",
    "halves" => "half",
    "loaves" => "loaf",
    "chillies" => "chilli",
    "chilies" => "chili",
    "cookies" => "cookie",
    "brownies" => "brownie",
    "pies" => "pie",
    "smoothies" => "smoothie",
    "calories" => "calorie"
  }

  @uncountable ~w(molasses hummus couscous asparagus grits series species)

  @units %{
    mass: [
      {"g", ~w(g gr gram grams gramme grammes)},
      {"kg", ~w(kg kgs kilo kilos kilogram kilograms kilogramme kilogrammes)},
      {"mg", ~w(mg milligram milligrams)},
      {"oz", ~w(oz ounce ounces)},
      {"lb", ~w(lb lbs pound pounds)}
    ],
    volume: [
      {"ml", ~w(ml mls millilitre millilitres milliliter milliliters)},
      {"l", ~w(l ltr litre litres liter liters)},
      {"cl", ~w(cl centilitre centilitres centiliter centiliters)},
      {"dl", ~w(dl decilitre decilitres deciliter deciliters)},
      {"tsp", ~w(tsp tsps teaspoon teaspoons)},
      {"tbsp", ~w(tbsp tbsps tbs tablespoon tablespoons)},
      {"cup", ~w(cup cups)},
      {"fl oz", ["fl oz", "fl. oz", "fluid ounce", "fluid ounces"]},
      {"pint", ~w(pint pints pt)}
    ],
    count: [{nil, ~w(item items piece pieces pc pcs whole)}]
  }

  @unit_lookup for {dimension, units} <- @units,
                   {canonical, spellings} <- units,
                   spelling <- spellings,
                   into: %{},
                   do: {spelling, {canonical, dimension}}

  @doc "Fills in an ingredient's key, canonical unit, dimension and scalable flag."
  @spec ingredient(Ingredient.t()) :: Ingredient.t()
  def ingredient(%Ingredient{} = ingredient) do
    {canonical_unit, dimension} = unit(ingredient.unit, ingredient.quantity)
    number? = is_struct(ingredient.quantity, Decimal)

    %{
      ingredient
      | key: key(ingredient.name),
        canonical_unit: canonical_unit,
        dimension: dimension,
        scalable: number?
    }
  end

  @doc """
  The merge key for an ingredient name: lower-case, single-spaced, with the
  last word singular.

      iex> Mealplan.Cooklang.Normalise.key("  Cherry  Tomatoes ")
      "cherry tomato"
  """
  @spec key(String.t()) :: String.t()
  def key(name) do
    name
    |> String.downcase()
    |> String.split()
    |> singular_last()
    |> Enum.join(" ")
  end

  @doc """
  The canonical unit and dimension for a unit as written. Without a unit, a
  numeric quantity counts items. Unknown units are lower-cased and made
  singular so "sprigs" and "sprig" match, with no dimension.
  """
  @spec unit(String.t() | nil, Decimal.t() | String.t() | nil) ::
          {String.t() | nil, Ingredient.dimension() | nil}
  def unit(nil, %Decimal{}), do: {nil, :count}
  def unit(nil, _quantity), do: {nil, nil}

  def unit(unit, _quantity) do
    spelling = unit |> String.downcase() |> String.split() |> Enum.join(" ")

    case Map.fetch(@unit_lookup, spelling) do
      {:ok, found} -> found
      :error -> {spelling |> String.trim_trailing(".") |> key(), nil}
    end
  end

  defp singular_last([]), do: []

  defp singular_last(words) do
    {last, rest} = List.pop_at(words, -1)
    rest ++ [singular(last)]
  end

  @doc false
  def singular(word) do
    cond do
      Map.has_key?(@irregular, word) -> Map.fetch!(@irregular, word)
      word in @uncountable -> word
      String.length(word) <= 3 -> word
      String.ends_with?(word, ["ss", "us", "is"]) -> word
      String.ends_with?(word, "ies") -> String.replace_suffix(word, "ies", "y")
      String.ends_with?(word, ~w(ches shes sses xes zes oes)) -> String.slice(word, 0..-3//1)
      String.ends_with?(word, "s") -> String.slice(word, 0..-2//1)
      true -> word
    end
  end
end
