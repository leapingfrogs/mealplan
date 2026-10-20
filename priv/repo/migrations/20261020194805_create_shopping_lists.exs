defmodule Mealplan.Repo.Migrations.CreateShoppingLists do
  use Ecto.Migration

  # The shopping list itself is computed from the plan; these keep only what
  # the household does to it (iteration 4 design, "Data"). Ticks and manual
  # items carry household_id in composite keys to their list, as elsewhere.
  def change do
    create table(:shopping_lists) do
      add :household_id, references(:households, on_delete: :delete_all), null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shopping_lists, [:household_id])
    create unique_index(:shopping_lists, [:household_id, :id])

    create constraint(:shopping_lists, :range_at_most_14_days,
             check: "ends_on >= starts_on AND ends_on - starts_on < 14"
           )

    # A ticked ingredient line, by key, with the quantity it showed when
    # ticked (to tell when more is needed).
    create table(:shopping_ticks) do
      add :household_id, :binary_id, null: false

      add :shopping_list_id,
          references(:shopping_lists,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :key, :string, null: false
      add :quantity, :map, null: false
      add :amount, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shopping_ticks, [:shopping_list_id, :key])

    create table(:shopping_items) do
      add :household_id, :binary_id, null: false

      add :shopping_list_id,
          references(:shopping_lists,
            on_delete: :delete_all,
            with: [household_id: :household_id],
            match: :full
          ),
          null: false

      add :text, :string, null: false
      add :position, :integer, null: false
      add :ticked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:shopping_items, [:shopping_list_id])

    create table(:staples) do
      add :household_id, references(:households, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:staples, [:household_id, :key])
  end
end
