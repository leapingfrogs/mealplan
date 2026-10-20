defmodule Mealplan.Recipes.RecipeIngredient do
  @moduledoc """
  One ingredient occurrence in a recipe's source, normalised for merging
  and scaling (see `Mealplan.Cooklang.Normalise`). Never edited directly.
  """
  use Ecto.Schema

  alias Mealplan.Cooklang.Ingredient
  alias Mealplan.Recipes.Recipe

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipe_ingredients" do
    field :household_id, :binary_id
    field :position, :integer
    field :name, :string
    field :key, :string
    field :quantity, :decimal
    field :quantity_text, :string
    field :unit, :string
    field :canonical_unit, :string
    field :dimension, Ecto.Enum, values: [:mass, :volume, :count]
    field :scalable, :boolean, default: false
    field :optional, :boolean, default: false
    field :note, :string

    belongs_to :recipe, Recipe
  end

  @doc "The row for a parsed ingredient (as a map for `Repo.insert_all/2`)."
  def from_parsed(%Ingredient{} = i, %Recipe{id: recipe_id, household_id: household_id}, position) do
    {quantity, quantity_text} =
      case i.quantity do
        %Decimal{} = number -> {number, nil}
        text -> {nil, text}
      end

    %{
      id: Ecto.UUID.generate(),
      household_id: household_id,
      recipe_id: recipe_id,
      position: position,
      name: truncate(i.name),
      key: truncate(i.key),
      quantity: quantity,
      quantity_text: truncate(quantity_text),
      unit: truncate(i.unit),
      canonical_unit: truncate(i.canonical_unit),
      dimension: i.dimension,
      scalable: i.scalable,
      optional: i.optional,
      note: truncate(i.note)
    }
  end

  # Columns are varchar(255), counted in code points; a name that long is a
  # typo, not data to keep.
  defp truncate(nil), do: nil
  defp truncate(text), do: text |> String.codepoints() |> Enum.take(255) |> Enum.join()
end
