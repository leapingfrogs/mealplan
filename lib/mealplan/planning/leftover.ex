defmodule Mealplan.Planning.Leftover do
  @moduledoc """
  One recipe of a planned meal that is eaten as leftovers of an earlier
  planned meal in the same week; the source is cooked bigger to cover it.
  """
  use Ecto.Schema

  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Recipes.Recipe

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "leftovers" do
    field :household_id, :binary_id

    belongs_to :planned_meal, PlannedMeal
    belongs_to :source_planned_meal, PlannedMeal
    belongs_to :recipe, Recipe
  end
end
