defmodule Mealplan.Repo.Migrations.CreateMeals do
  use Ecto.Migration

  def change do
    create table(:meals) do
      add :household_id, references(:households, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Target of composite foreign keys (household_id, meal_id).
    create unique_index(:meals, [:household_id, :id])

    # One active meal per name, so pickers aren't ambiguous and planning a
    # recipe directly can find its one-recipe meal.
    create unique_index(:meals, ["household_id", "lower(name)"],
             where: "archived_at IS NULL",
             name: :meals_household_id_name_index
           )

    # Both references carry the household, so a meal can only ever contain
    # its own household's recipes.
    create table(:meal_recipes) do
      add :household_id, :binary_id, null: false

      add :meal_id,
          references(:meals,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :recipe_id,
          references(:recipes,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :position, :integer, null: false
    end

    create unique_index(:meal_recipes, [:meal_id, :recipe_id])
    create index(:meal_recipes, [:recipe_id])
  end
end
