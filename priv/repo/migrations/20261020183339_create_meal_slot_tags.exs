defmodule Mealplan.Repo.Migrations.CreateMealSlotTags do
  use Ecto.Migration

  # Which slots a meal suits. Both references carry the household, so a tag
  # can't cross households. Deleting a meal or a slot outright removes its
  # tags; archiving either keeps them.
  def change do
    create table(:meal_slot_tags) do
      add :household_id, :binary_id, null: false

      add :meal_id,
          references(:meals,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :meal_slot_id,
          references(:meal_slots,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:meal_slot_tags, [:meal_id, :meal_slot_id])
    create index(:meal_slot_tags, [:meal_slot_id])
  end
end
