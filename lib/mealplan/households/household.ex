defmodule Mealplan.Households.Household do
  @moduledoc """
  A household: the people who plan and share meals. Everything else in the
  app belongs to one.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Accounts.User
  alias Mealplan.Households.MealSlot

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "households" do
    field :name, :string
    # IANA name, e.g. "Europe/London": defines "today" and the planning week.
    field :time_zone, :string
    # Default servings for newly planned meals.
    field :usually_feeding, :integer

    belongs_to :owner, User
    has_many :members, User
    has_many :meal_slots, MealSlot

    timestamps(type: :utc_datetime)
  end

  @max_feeding 50

  @doc """
  Changeset for creating or editing a household. The owner is set by the
  caller, never cast.
  """
  def changeset(household, attrs) do
    household
    |> cast(attrs, [:name, :time_zone, :usually_feeding])
    |> update_change(:name, &trim/1)
    |> validate_required([:name, :time_zone, :usually_feeding])
    |> validate_length(:name, max: 80)
    |> validate_number(:usually_feeding, greater_than: 0, less_than_or_equal_to: @max_feeding)
    |> validate_change(:time_zone, &validate_time_zone/2)
    |> check_constraint(:usually_feeding, name: :usually_feeding_positive)
  end

  # Blank names arrive as nil (Ecto treats whitespace-only as empty).
  defp trim(nil), do: nil
  defp trim(name), do: String.trim(name)

  defp validate_time_zone(:time_zone, time_zone) do
    case DateTime.now(time_zone) do
      {:ok, _} -> []
      {:error, _} -> [time_zone: "is not a known time zone"]
    end
  end
end
