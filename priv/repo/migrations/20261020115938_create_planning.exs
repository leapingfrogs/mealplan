defmodule Mealplan.Repo.Migrations.CreatePlanning do
  use Ecto.Migration

  # Every reference carries household_id (composite keys), so plans can only
  # point at their own household's slots, meals and recipes.
  #
  # Planned meals reference slots and meals with NO ACTION rather than
  # RESTRICT: deleting a household cascades to both sides in one statement,
  # and NO ACTION checks only at its end. Deleting a slot or meal that plans
  # still use is refused; the archive rule (a later task) decides what
  # happens instead.
  def change do
    create table(:planned_meals) do
      add :household_id, references(:households, on_delete: :delete_all), null: false
      add :date, :date, null: false

      add :meal_slot_id,
          references(:meal_slots,
            on_delete: :nothing,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :meal_id,
          references(:meals,
            on_delete: :nothing,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :servings, :integer, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:planned_meals, [:household_id, :id])
    create index(:planned_meals, [:household_id, :date])
    create index(:planned_meals, [:meal_slot_id])
    create index(:planned_meals, [:meal_id])
    create constraint(:planned_meals, :servings_positive, check: "servings > 0")

    # One row per recipe of a later planned meal that is eaten as leftovers
    # of an earlier one. The rows go when either planned meal does.
    create table(:leftovers) do
      add :household_id, :binary_id, null: false

      add :planned_meal_id,
          references(:planned_meals,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :source_planned_meal_id,
          references(:planned_meals,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      # A deleted recipe leaves its meals, so its leftover links go too.
      add :recipe_id,
          references(:recipes,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false
    end

    create unique_index(:leftovers, [:planned_meal_id, :recipe_id])
    create index(:leftovers, [:source_planned_meal_id])
    create index(:leftovers, [:recipe_id])

    create constraint(:leftovers, :not_its_own_source,
             check: "planned_meal_id <> source_planned_meal_id"
           )

    create table(:slot_skips) do
      add :household_id, :binary_id, null: false
      add :date, :date, null: false

      add :meal_slot_id,
          references(:meal_slots,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:slot_skips, [:meal_slot_id, :date])
    create index(:slot_skips, [:household_id, :date])
  end
end
