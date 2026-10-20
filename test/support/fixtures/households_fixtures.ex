defmodule Mealplan.HouseholdsFixtures do
  @moduledoc """
  Test helpers for creating households through the `Mealplan.Households`
  context.
  """
  alias Mealplan.Accounts.Scope
  alias Mealplan.AccountsFixtures
  alias Mealplan.Households

  def valid_household_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Household #{System.unique_integer([:positive])}",
      time_zone: "Europe/London",
      usually_feeding: 4
    })
  end

  @doc """
  Creates a household owned by `user` (a new user if not given) and returns
  `%{user: user, household: household, scope: scope}`, where the scope
  includes the household.
  """
  def household_fixture(user \\ AccountsFixtures.user_fixture(), attrs \\ %{}) do
    {:ok, household} =
      user
      |> Scope.for_user()
      |> Households.create_household(valid_household_attributes(attrs))

    user = %{user | household_id: household.id, household: household}
    %{user: user, household: household, scope: Scope.for_user(user)}
  end

  @doc """
  Adds a new (non-owner) member to `household` and returns
  `%{user: user, scope: scope}`. Joining by invitation replaces this once
  invitations exist.
  """
  def member_fixture(household) do
    user =
      AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(household_id: household.id)
      |> Mealplan.Repo.update!()
      |> Map.put(:household, household)

    %{user: user, scope: Scope.for_user(user)}
  end
end
