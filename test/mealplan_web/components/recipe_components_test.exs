defmodule MealplanWeb.RecipeComponentsTest do
  use ExUnit.Case, async: true

  import MealplanWeb.RecipeComponents

  doctest MealplanWeb.RecipeComponents

  test "format_quantity/1 and amount/2" do
    assert format_quantity(Decimal.new("0.5")) == "½"
    assert format_quantity(Decimal.new("3")) == "3"
    assert format_quantity(Decimal.new("2.50")) == "2½"
    assert format_quantity("few") == "few"
    assert format_quantity(nil) == nil
    assert amount(Decimal.new(250), "g") == "250 g"
    assert amount(nil, "pinch") == "pinch"
    assert amount(nil, nil) == nil
  end
end
