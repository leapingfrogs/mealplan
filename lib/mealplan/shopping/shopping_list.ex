defmodule Mealplan.Shopping.ShoppingList do
  @moduledoc """
  A household's shopping list: the date range it covers. One per household;
  what to buy is computed from the plan (`Mealplan.Shopping.view/1`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Households.Household
  alias Mealplan.Shopping.Item
  alias Mealplan.Shopping.Tick

  @max_days 14

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shopping_lists" do
    field :starts_on, :date
    field :ends_on, :date

    belongs_to :household, Household
    has_many :ticks, Tick
    has_many :items, Item, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc "The longest range, in days."
  def max_days, do: @max_days

  @doc "A changeset for the range."
  def range_changeset(list, attrs) do
    list
    |> cast(attrs, [:starts_on, :ends_on])
    |> validate_required([:starts_on, :ends_on])
    |> validate_range()
    |> check_constraint(:ends_on, name: :range_at_most_14_days, message: "is too far away")
  end

  defp validate_range(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    cond do
      is_nil(starts_on) or is_nil(ends_on) ->
        changeset

      Date.before?(ends_on, starts_on) ->
        add_error(changeset, :ends_on, "is before the start")

      Date.diff(ends_on, starts_on) >= @max_days ->
        add_error(changeset, :ends_on, "is more than #{@max_days} days on")

      true ->
        changeset
    end
  end
end
