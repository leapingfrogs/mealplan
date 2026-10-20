defmodule Mealplan.Cooklang.CanonicalTest do
  @moduledoc """
  Cooklang's canonical parser tests (test/support/fixtures/cooklang), one
  ExUnit test per case. The cases describe a simplified view of the result,
  so the parse is mapped into that shape before comparing.
  """
  use ExUnit.Case, async: true

  alias Mealplan.Cooklang
  alias Mealplan.Cooklang.Cookware
  alias Mealplan.Cooklang.Ingredient
  alias Mealplan.Cooklang.Step
  alias Mealplan.Cooklang.Text
  alias Mealplan.Cooklang.Timer

  @path Path.expand("../../support/fixtures/cooklang/canonical.yaml", __DIR__)
  @external_resource @path

  %{"version" => 8, "tests" => cases} = YamlElixir.read_from_file!(@path)

  for {name, %{"source" => source, "result" => expected}} <- Enum.sort(cases) do
    @source source
    @expected expected

    test name do
      recipe = Cooklang.parse(@source)

      assert [] = recipe.warnings
      assert recipe.metadata == @expected["metadata"]
      assert length(recipe.sections) <= 1

      assert steps(recipe) ==
               Enum.map(@expected["steps"], &Enum.map(&1, fn item -> expected(item) end))
    end
  end

  defp steps(recipe) do
    for section <- recipe.sections, %Step{items: items} <- section.blocks do
      Enum.map(items, &actual/1)
    end
  end

  defp actual(%Text{value: value}), do: %{"type" => "text", "value" => value}

  defp actual(%Ingredient{} = i) do
    %{
      "type" => "ingredient",
      "name" => i.name,
      "quantity" => quantity(i.quantity, "some"),
      "units" => i.unit || "",
      "optional" => i.optional
    }
  end

  defp actual(%Cookware{} = c) do
    %{
      "type" => "cookware",
      "name" => c.name,
      "quantity" => quantity(c.quantity, 1.0),
      "optional" => c.optional
    }
  end

  defp actual(%Timer{} = t) do
    %{
      "type" => "timer",
      "name" => t.name || "",
      "quantity" => quantity(t.quantity, ""),
      "units" => t.unit || ""
    }
  end

  # The cases omit `optional: false` and give cookware an unused "units".
  defp expected(%{"type" => "text"} = item), do: item

  defp expected(%{"type" => "timer"} = item) do
    Map.update!(item, "quantity", &number/1)
  end

  defp expected(%{"type" => type} = item) do
    item = item |> Map.put_new("optional", false) |> Map.update!("quantity", &number/1)
    if type == "cookware", do: Map.delete(item, "units"), else: item
  end

  defp quantity(nil, default), do: default
  defp quantity(%Decimal{} = number, _default), do: Decimal.to_float(number)
  defp quantity(text, _default), do: text

  defp number(n) when is_number(n), do: n / 1
  defp number(text), do: text
end
