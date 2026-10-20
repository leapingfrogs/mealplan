defmodule Mealplan.Repo.Migrations.CreateRecipes do
  use Ecto.Migration

  def change do
    create table(:recipes) do
      add :household_id, references(:households, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :servings, :integer, null: false
      add :source, :text, null: false, default: ""
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Target of composite foreign keys (household_id, recipe_id), so rows
    # that reference a recipe can never cross households.
    create unique_index(:recipes, [:household_id, :id])
    create index(:recipes, [:household_id, "lower(name)"])

    create constraint(:recipes, :servings_positive, check: "servings > 0")

    # Derived from recipes.source on every save; rows so the shopping list
    # can merge and scale ingredients in SQL.
    create table(:recipe_ingredients) do
      add :household_id, :binary_id, null: false

      add :recipe_id,
          references(:recipes,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :position, :integer, null: false
      add :name, :string, null: false
      add :key, :string, null: false
      # A number, or the text as written ("few") in quantity_text, or
      # neither ("some").
      add :quantity, :decimal
      add :quantity_text, :string
      add :unit, :string
      add :canonical_unit, :string
      add :dimension, :string
      add :scalable, :boolean, null: false, default: false
      add :optional, :boolean, null: false, default: false
      add :note, :string
    end

    create index(:recipe_ingredients, [:recipe_id, :position])
    create index(:recipe_ingredients, [:household_id, :key])

    create constraint(:recipe_ingredients, :dimension_valid,
             check: "dimension IN ('mass', 'volume', 'count')"
           )
  end
end
