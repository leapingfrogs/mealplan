defmodule Mealplan.Meals.MealRecipe do
  @moduledoc "A recipe in a meal, in the meal's order."
  use Ecto.Schema

  alias Mealplan.Meals.Meal
  alias Mealplan.Recipes.Recipe

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_recipes" do
    field :household_id, :binary_id
    field :position, :integer

    belongs_to :meal, Meal
    belongs_to :recipe, Recipe
  end
end
