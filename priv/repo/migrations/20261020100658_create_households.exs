defmodule Mealplan.Repo.Migrations.CreateHouseholds do
  use Ecto.Migration

  def change do
    create table(:households) do
      add :name, :string, null: false
      add :owner_id, references(:users, on_delete: :restrict), null: false
      add :time_zone, :string, null: false
      add :usually_feeding, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:households, [:owner_id])

    create constraint(:households, :usually_feeding_positive, check: "usually_feeding > 0")

    alter table(:users) do
      # One household per user; leaving or removal sets it back to null.
      add :household_id, references(:households, on_delete: :nilify_all)
    end

    create index(:users, [:household_id])

    create table(:meal_slots) do
      add :household_id, references(:households, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false
      add :default_key, :string
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Target of composite foreign keys (household_id, meal_slot_id) from later
    # tables, so a reference can never cross households.
    create unique_index(:meal_slots, [:household_id, :id])

    create unique_index(:meal_slots, ["household_id", "lower(name)"],
             where: "archived_at IS NULL",
             name: :meal_slots_household_id_name_index
           )

    create constraint(:meal_slots, :default_key_valid,
             check: "default_key IN ('breakfast', 'lunch', 'dinner', 'snack')"
           )
  end
end
