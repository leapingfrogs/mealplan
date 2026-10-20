defmodule Mealplan.MealsFixtures do
  @moduledoc "Test helpers for creating meals through `Mealplan.Meals`."

  alias Mealplan.Meals

  @doc "Creates a meal containing `recipes` in order."
  def meal_fixture(scope, attrs \\ %{}, recipes \\ []) do
    {:ok, meal} =
      Meals.create_meal(
        scope,
        Enum.into(attrs, %{name: "Meal #{System.unique_integer([:positive])}"})
      )

    for recipe <- recipes, do: {:ok, _} = Meals.add_recipe(scope, meal.id, recipe.id)
    Meals.get_meal!(scope, meal.id)
  end
end
