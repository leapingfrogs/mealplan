defmodule Mealplan.Planning.PlannedMeal do
  @moduledoc """
  A meal planned in a slot on a (household-local) date, for a number of
  servings. `position` orders several meals in the same slot.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Households.Household
  alias Mealplan.Households.MealSlot
  alias Mealplan.Meals.Meal
  alias Mealplan.Planning.Leftover

  @max_servings 100

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "planned_meals" do
    field :date, :date
    field :servings, :integer
    field :position, :integer

    belongs_to :household, Household
    belongs_to :meal_slot, MealSlot
    belongs_to :meal, Meal
    # Recipes of this meal eaten as leftovers of an earlier one.
    has_many :leftovers, Leftover
    # Leftovers that later meals take from this one.
    has_many :leftovers_taken, Leftover, foreign_key: :source_planned_meal_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the servings a meal is planned for."
  def servings_changeset(planned_meal, attrs) do
    planned_meal
    |> cast(attrs, [:servings])
    |> validate_required([:servings])
    |> validate_number(:servings, greater_than: 0, less_than_or_equal_to: @max_servings)
    |> check_constraint(:servings, name: :servings_positive)
  end
end
