defmodule Mealplan.Households.MealSlot do
  @moduledoc """
  A named time of eating for a household (Breakfast, Lunch, ...), in the
  household's order within a day.
  """
  use Ecto.Schema

  alias Mealplan.Households.Household

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_slots" do
    field :name, :string
    field :position, :integer
    # Which default this slot is, so "restore defaults" can re-create
    # missing ones without touching custom slots.
    field :default_key, :string
    field :archived_at, :utc_datetime

    belongs_to :household, Household

    timestamps(type: :utc_datetime)
  end

  @defaults [
    {"breakfast", "Breakfast"},
    {"lunch", "Lunch"},
    {"dinner", "Dinner"},
    {"snack", "Snack"}
  ]

  @doc "The default slots as `{default_key, name}`, in day order."
  def defaults, do: @defaults
end
