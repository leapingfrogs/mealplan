defmodule Mealplan.Shopping.QuantityTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mealplan.Cooklang.Normalise
  alias Mealplan.Shopping.Quantity

  doctest Quantity

  # A row as the parser would store it for `quantity` and `unit`.
  defp row(quantity, unit \\ nil) do
    quantity =
      cond do
        is_number(quantity) -> Decimal.new("#{quantity}")
        is_binary(quantity) and quantity =~ ~r/^[\d.]+$/ -> Decimal.new(quantity)
        true -> quantity
      end

    {canonical, dimension} = Normalise.unit(unit, quantity)

    {number, text} =
      if is_struct(quantity, Decimal), do: {quantity, nil}, else: {nil, quantity}

    %{
      quantity: number,
      quantity_text: text,
      unit: unit,
      canonical_unit: canonical,
      dimension: dimension
    }
  end

  defp shown(rows, scale \\ 1) do
    rows
    |> Enum.map(&Quantity.new(&1, Decimal.new("#{scale}")))
    |> Quantity.sum()
    |> Quantity.to_string()
  end

  describe "merging and units" do
    test "metric mass adds up across mg, g and kg, shown in the larger unit from 1000" do
      assert shown([row(400, "g"), row("0.5", "kg")]) == "900 g"
      assert shown([row(400, "grams"), row(1, "kg")]) == "1.4 kg"
      assert shown([row(250, "mg")]) == "250 mg"
      assert shown([row(500, "mg"), row(1, "g")]) == "1.5 g"
    end

    test "metric volume adds up across ml, cl, dl and l" do
      assert shown([row(250, "ml"), row(1, "dl"), row(5, "cl")]) == "400 ml"
      assert shown([row("0.75", "l"), row(500, "ml")]) == "1.25 l"
    end

    test "other units add up only with themselves, side by side with metric" do
      assert shown([row(2, "tbsp"), row(1, "tablespoon"), row(100, "ml")]) == "100 ml + 3 tbsp"
      assert shown([row(2, "cups"), row(1, "tsp")]) == "2 cups + 1 tsp"
      assert shown([row(1, "tin"), row(2, "tins")]) == "3 tins"
      assert shown([row(1, "Clove")]) == "1 Clove"
      assert shown([row(1, "clove")], 3) == "3 clove"
    end

    test "counts add up and round up to a whole number" do
      assert shown([row(1), row("0.5")]) == "2"
      assert shown([row(1, "piece"), row(2)]) == "3"
      assert shown([row(1)], "1.5") == "2"
      assert shown([row(2)], "1.5") == "3"
    end

    test "text quantities are listed once each; no quantity is some, unless there's more" do
      assert shown([row("a handful"), row("a handful"), row("a few")]) == "a few + a handful"
      assert shown([row(nil)]) == "some"
      assert shown([row(nil), row(1, "tsp")]) == "1 tsp"
      assert shown([row(" ")]) == "some"
      assert shown([]) == "some"
    end

    test "amounts round up to what you can buy, without trailing zeros" do
      # Metric: 0.5 under 10, 5 under 100, 25 under 1000, then 50.
      assert shown([row(100, "g")], "0.3333") == "35 g"
      assert shown([row(200, "g")], "3.3333") == "675 g"
      assert shown([row(500, "g")], "3.3333") == "1.7 kg"
      assert shown([row("2.3", "g")]) == "2.5 g"
      assert shown([row("0.12", "g")]) == "150 mg"
      assert shown([row(300, "ml")], "1.6666") == "500 ml"
      # Measuring units to the nearest half; things bought whole round up.
      assert shown([row(2, "tbsp")], "1.6667") == "3.5 tbsp"
      assert shown([row("1.50", "tbsp")]) == "1.5 tbsp"
      assert shown([row(1, "tbsp")], 2) == "2 tbsp"
      assert shown([row(2, "tins")], "2.6667") == "6 tins"
      assert shown([row(4, "cloves")], "4.0833") == "17 cloves"
      assert shown([row(1, "thumb")], "3.3333") == "4 thumb"
    end

    test "more since ticked compares the rounded amounts" do
      before = Quantity.new(row(660, "g"))
      assert Quantity.more(Quantity.new(row(670, "g")), before) == nil
      assert Quantity.to_string(Quantity.more(Quantity.new(row(680, "g")), before)) == "25 g"
    end

    test "empty?/1" do
      assert Quantity.empty?(%Quantity{})
      refute Quantity.empty?(Quantity.new(row(nil)))
    end
  end

  describe "more/2 and storing" do
    defp q(rows, scale \\ 1),
      do: rows |> Enum.map(&Quantity.new(&1, Decimal.new("#{scale}"))) |> Quantity.sum()

    test "what grew, by how much, as shown" do
      before = q([row(400, "g"), row(2, "tbsp"), row(1), row("a pinch")])

      assert Quantity.more(before, before) == nil
      assert Quantity.more(q([row(400, "g")]), before) == nil

      grown = q([row(1, "kg"), row(3, "tbsp"), row(1), row(250, "ml"), row("a handful")])

      assert Quantity.to_string(Quantity.more(grown, before)) ==
               "600 g + 250 ml + 1 tbsp + a handful"
    end

    test "counts compare as rounded up" do
      assert Quantity.more(q([row("1.8")]), q([row("1.5")])) == nil
      assert Quantity.to_string(Quantity.more(q([row("2.1")]), q([row("1.5")]))) == "1"
    end

    test "to_map/1 and from_map/1 keep the amounts" do
      quantity = q([row("1.5", "kg"), row(2, "tins"), row(3), row("a pinch"), row(nil)], 2)

      back =
        quantity |> Quantity.to_map() |> Jason.encode!() |> Jason.decode!() |> Quantity.from_map()

      assert Quantity.more(quantity, back) == nil
      assert Quantity.more(back, quantity) == nil
      assert back.some

      assert Quantity.from_map(%{"mass" => "lots", "units" => %{"tin" => 3}, "texts" => [1]}) ==
               %Quantity{}
    end
  end

  describe "properties" do
    defp quantity do
      gen all n <- integer(1..5000),
              unit <- member_of([nil, "g", "kg", "mg", "ml", "l", "cl", "tbsp", "cup", "tin"]),
              scale <- member_of(["0.5", "1", "1.5", "2", "3"]) do
        Quantity.new(row(n, unit), Decimal.new(scale))
      end
    end

    property "adding is order-independent" do
      check all quantities <- list_of(quantity(), max_length: 6) do
        forward = quantities |> Quantity.sum() |> Quantity.to_string()
        backward = quantities |> Enum.reverse() |> Quantity.sum() |> Quantity.to_string()
        assert forward == backward
      end
    end

    property "grams and kilograms are the same thing" do
      check all grams <- integer(1..100_000) do
        kilos = Decimal.div(grams, 1000)
        assert shown([row(grams, "g")]) == shown([row(Decimal.to_string(kilos), "kg")])
      end
    end

    property "counts are always whole" do
      check all n <- integer(1..50), scale <- member_of(["0.25", "0.5", "1.5", "2.3333"]) do
        assert shown([row(n)], scale) =~ ~r/^\d+$/
      end
    end
  end
end
