defmodule Mealplan.Repo.Migrations.CreateHouseholdInvitations do
  use Ecto.Migration

  def change do
    create table(:household_invitations) do
      add :household_id, references(:households, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :declined_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:household_invitations, [:email])

    # At most one open invitation per household and address. An expired one
    # is still "open" here, so inviting again renews it rather than adding a
    # second row.
    create unique_index(:household_invitations, [:household_id, :email],
             where: "accepted_at IS NULL AND declined_at IS NULL AND revoked_at IS NULL",
             name: :household_invitations_open_index
           )
  end
end
