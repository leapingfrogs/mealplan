defmodule Mealplan.Households.MealSlot do
  @moduledoc """
  A named time of eating for a household (Breakfast, Lunch, ...), in the
  household's order within a day.
  """
  use Ecto.Schema

  import Ecto.Changeset

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

  @doc """
  The defaults missing from `slots`. A default counts as present when a slot
  is that default (even renamed) or another slot already has its name.
  """
  def missing_defaults(slots) do
    keys = MapSet.new(slots, & &1.default_key)
    names = MapSet.new(slots, &String.downcase(&1.name))

    Enum.reject(@defaults, fn {key, name} ->
      key in keys or String.downcase(name) in names
    end)
  end

  @doc "Changeset for the name, the only field people edit directly."
  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:name])
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 40)
    |> unique_constraint(:name,
      name: :meal_slots_household_id_name_index,
      message: "is already a meal slot"
    )
  end

  defp trim(nil), do: nil
  defp trim(name), do: String.trim(name)
end
