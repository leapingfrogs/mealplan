defmodule Mealplan.Recipes.Recipe do
  @moduledoc """
  A household's recipe. `source` (Cooklang) is the source of truth; the
  ingredient rows are rebuilt from it on every save.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Accounts.User
  alias Mealplan.Households.Household
  alias Mealplan.Recipes.RecipeIngredient

  @max_source 50_000
  @max_servings 100

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipes" do
    field :name, :string
    field :servings, :integer
    field :source, :string, default: ""
    field :archived_at, :utc_datetime
    # Filled by list queries.
    field :ingredient_count, :integer, virtual: true

    belongs_to :household, Household
    belongs_to :created_by, User
    has_many :ingredients, RecipeIngredient, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the recipe form."
  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:name, :servings, :source])
    |> update_change(:name, &trim/1)
    |> update_change(:source, &normalise_source/1)
    |> validate_required([:name, :servings])
    |> validate_length(:name, max: 120)
    |> validate_length(:source, max: @max_source)
    |> validate_number(:servings, greater_than: 0, less_than_or_equal_to: @max_servings)
    |> check_constraint(:servings, name: :servings_positive)
  end

  defp trim(nil), do: nil
  defp trim(name), do: String.trim(name)

  # Browsers submit textareas with CRLF line endings.
  defp normalise_source(nil), do: ""
  defp normalise_source(source), do: String.replace(source, "\r\n", "\n")
end
