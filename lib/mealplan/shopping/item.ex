defmodule Mealplan.Shopping.Item do
  @moduledoc ~s{Something added to the shopping list by hand ("Kitchen roll", "Milk 2 l").}
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Shopping.ShoppingList

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shopping_items" do
    field :household_id, :binary_id
    field :text, :string
    field :position, :integer
    field :ticked_at, :utc_datetime

    belongs_to :shopping_list, ShoppingList

    timestamps(type: :utc_datetime)
  end

  @doc "A changeset for the item's text."
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:text])
    |> update_change(:text, &collapse_spaces/1)
    |> validate_required([:text])
    |> validate_length(:text, max: 120)
  end

  defp collapse_spaces(text), do: text |> String.split() |> Enum.join(" ")
end
