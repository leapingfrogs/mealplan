defmodule Mealplan.Meals.MealRecipe do
  @moduledoc """
  A recipe in a meal, in the meal's order. A recipe taken out of a meal
  that past plans used keeps its row with `removed_on` (a household-local
  date), so those planned meals keep the recipes they had; current recipes
  have no `removed_on`.
  """
  use Ecto.Schema

  alias Mealplan.Meals.Meal
  alias Mealplan.Recipes.Recipe

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_recipes" do
    field :household_id, :binary_id
    field :position, :integer
    field :removed_on, :date

    belongs_to :meal, Meal
    belongs_to :recipe, Recipe
  end
end
