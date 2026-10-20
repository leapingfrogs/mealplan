defmodule Mealplan.Meals.MealSlotTag do
  @moduledoc "Tags a meal with a meal slot it suits."
  use Ecto.Schema

  alias Mealplan.Households.MealSlot
  alias Mealplan.Meals.Meal

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_slot_tags" do
    field :household_id, :binary_id

    belongs_to :meal, Meal
    belongs_to :meal_slot, MealSlot

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
