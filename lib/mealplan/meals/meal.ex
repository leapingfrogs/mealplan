defmodule Mealplan.Meals.Meal do
  @moduledoc """
  Something a household eats at one sitting: zero or more recipes in order
  ("Eat out" has none).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Accounts.User
  alias Mealplan.Households.Household
  alias Mealplan.Households.MealSlot
  alias Mealplan.Meals.MealRecipe
  alias Mealplan.Meals.MealSlotTag

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meals" do
    field :name, :string
    field :archived_at, :utc_datetime
    # Filled by list queries.
    field :recipe_count, :integer, virtual: true

    belongs_to :household, Household
    belongs_to :created_by, User
    # The current recipes; `recipe_history` also has removed ones (see
    # `Mealplan.Meals.recipes_on/3`).
    has_many :meal_recipes, MealRecipe, where: [removed_on: nil], preload_order: [asc: :position]
    has_many :recipe_history, MealRecipe, preload_order: [asc: :position]
    # The active slots it suits, in day order (read only; see
    # `Mealplan.Meals.set_slots/3`). Tags on archived slots are kept but hidden.
    many_to_many :slots, MealSlot,
      join_through: MealSlotTag,
      join_keys: [meal_id: :id, meal_slot_id: :id],
      where: [archived_at: nil],
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the meal's name."
  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [:name])
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> unique_constraint(:name,
      name: :meals_household_id_name_index,
      message: "is already a meal"
    )
  end

  defp trim(nil), do: nil
  defp trim(name), do: String.trim(name)
end
