defmodule Mealplan.RecipesFixtures do
  @moduledoc "Test helpers for creating recipes through `Mealplan.Recipes`."

  alias Mealplan.Recipes

  def recipe_fixture(scope, attrs \\ %{}) do
    {:ok, recipe} =
      Recipes.create_recipe(
        scope,
        Enum.into(attrs, %{name: "Recipe #{System.unique_integer([:positive])}", servings: 4})
      )

    recipe
  end
end
