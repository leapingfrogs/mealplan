defmodule Mealplan.Planning.SlotSkip do
  @moduledoc "A slot nobody needs planning on a date (eating out, away); counts as planned."
  use Ecto.Schema

  alias Mealplan.Households.MealSlot

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "slot_skips" do
    field :household_id, :binary_id
    field :date, :date

    belongs_to :meal_slot, MealSlot

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
