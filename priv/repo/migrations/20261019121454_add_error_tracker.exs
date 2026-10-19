defmodule Mealplan.Repo.Migrations.AddErrorTracker do
  use Ecto.Migration

  # Pinned so later ErrorTracker upgrades add their own migrations explicitly.
  def up, do: ErrorTracker.Migration.up(version: 5)
  def down, do: ErrorTracker.Migration.down(version: 1)
end
