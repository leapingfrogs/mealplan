defmodule Mealplan.Repo.Migrations.AddHistoryToMealRecipes do
  use Ecto.Migration

  # Taking a recipe out of a meal that past plans used keeps the link with
  # the (household-local) date it was removed, so those planned meals still
  # resolve to the recipes they had, archived ones included.
  def change do
    alter table(:meal_recipes) do
      add :removed_on, :date
    end

    # A recipe is in a meal at most once at a time; it may come back later.
    drop unique_index(:meal_recipes, [:meal_id, :recipe_id])

    create unique_index(:meal_recipes, [:meal_id, :recipe_id],
             where: "removed_on IS NULL",
             name: :meal_recipes_current_index
           )
  end
end
