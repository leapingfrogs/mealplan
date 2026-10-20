defmodule Mealplan.Shopping.Staple do
  @moduledoc """
  An ingredient the household always has (salt, olive oil), left off the
  shopping list. Matched by the ingredient `key`
  (`Mealplan.Cooklang.Normalise.key/1`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Cooklang.Normalise
  alias Mealplan.Households.Household

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "staples" do
    field :key, :string
    field :name, :string

    belongs_to :household, Household

    timestamps(type: :utc_datetime)
  end

  @doc "A changeset for the staple's name; the key follows from it."
  def changeset(staple, attrs) do
    staple
    |> cast(attrs, [:name])
    |> update_change(:name, &(&1 |> String.split() |> Enum.join(" ")))
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> put_key()
    |> unique_constraint(:name,
      name: :staples_household_id_key_index,
      message: "is already a staple"
    )
  end

  defp put_key(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :key, Normalise.key(name))
    end
  end
end
