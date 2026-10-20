defmodule Mealplan.Shopping.Tick do
  @moduledoc """
  A ticked ingredient line, by key, with the quantity it showed when ticked
  (`Mealplan.Shopping.Quantity.to_map/1`) so the list can tell when more is
  needed.
  """
  use Ecto.Schema

  alias Mealplan.Shopping.ShoppingList

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shopping_ticks" do
    field :household_id, :binary_id
    field :key, :string
    field :quantity, :map
    field :amount, :string

    belongs_to :shopping_list, ShoppingList

    timestamps(type: :utc_datetime)
  end
end
