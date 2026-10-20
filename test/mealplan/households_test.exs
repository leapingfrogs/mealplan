defmodule Mealplan.HouseholdsTest do
  use Mealplan.DataCase, async: true

  import Mealplan.AccountsFixtures
  import Mealplan.HouseholdsFixtures

  alias Mealplan.Accounts
  alias Mealplan.Accounts.Scope
  alias Mealplan.Accounts.User
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Households.MealSlot

  describe "create_household/2" do
    test "creates the household owned by the user, who becomes its member" do
      user = user_fixture()

      assert {:ok, %Household{} = household} =
               Households.create_household(Scope.for_user(user), %{
                 name: "  The Davies household  ",
                 time_zone: "Europe/London",
                 usually_feeding: 4
               })

      assert household.name == "The Davies household"
      assert household.owner_id == user.id
      assert household.time_zone == "Europe/London"
      assert household.usually_feeding == 4
      assert Repo.get!(User, user.id).household_id == household.id
    end

    test "adds the default meal slots in day order" do
      %{scope: scope} = household_fixture()

      assert [
               %MealSlot{name: "Breakfast", default_key: "breakfast", position: 0},
               %MealSlot{name: "Lunch", default_key: "lunch", position: 1},
               %MealSlot{name: "Dinner", default_key: "dinner", position: 2},
               %MealSlot{name: "Snack", default_key: "snack", position: 3}
             ] = Households.list_meal_slots(scope)
    end

    test "validates name, usually feeding and time zone" do
      scope = Scope.for_user(user_fixture())

      assert {:error, changeset} =
               Households.create_household(scope, %{
                 name: " ",
                 usually_feeding: 0,
                 time_zone: "Mars/Olympus"
               })

      assert %{
               name: ["can't be blank"],
               usually_feeding: ["must be greater than 0"],
               time_zone: ["is not a known time zone"]
             } = errors_on(changeset)

      assert {:error, changeset} =
               Households.create_household(
                 scope,
                 valid_household_attributes(name: String.duplicate("a", 81), usually_feeding: 51)
               )

      assert %{name: [_], usually_feeding: ["must be less than or equal to 50"]} =
               errors_on(changeset)

      assert Repo.aggregate(Household, :count) == 0
    end

    test "refuses a user who already has a household" do
      %{scope: scope} = household_fixture()

      assert Households.create_household(scope, valid_household_attributes()) ==
               {:error, :already_in_household}
    end

    test "refuses, and rolls back, when the user joined a household since the scope was built" do
      user = user_fixture()
      stale_scope = Scope.for_user(user)
      household_fixture(user)

      assert Households.create_household(stale_scope, valid_household_attributes()) ==
               {:error, :already_in_household}

      assert Repo.aggregate(Household, :count) == 1
      assert Repo.aggregate(MealSlot, :count) == 4
    end
  end

  describe "owner?/1" do
    test "is true only for the household's owner" do
      %{scope: owner_scope, household: household} = household_fixture()
      %{scope: member_scope} = member_fixture(household)

      assert Households.owner?(owner_scope)
      refute Households.owner?(member_scope)
    end
  end

  describe "update_household/2" do
    test "lets the owner update the details and tells the household" do
      %{scope: scope} = household_fixture()
      :ok = Households.subscribe(scope)

      assert {:ok, household} =
               Households.update_household(scope, %{
                 name: "Renamed",
                 usually_feeding: 6,
                 time_zone: "America/New_York"
               })

      assert %{name: "Renamed", usually_feeding: 6, time_zone: "America/New_York"} = household
      assert_receive {:household_updated, %Household{name: "Renamed"}}
    end

    test "validates like creation" do
      %{scope: scope} = household_fixture()

      assert {:error, changeset} =
               Households.update_household(scope, %{name: "", time_zone: "Nowhere/Land"})

      assert %{name: ["can't be blank"], time_zone: ["is not a known time zone"]} =
               errors_on(changeset)
    end

    test "refuses members who aren't the owner" do
      %{household: household} = household_fixture(user_fixture(), %{name: "Original"})
      %{scope: member_scope} = member_fixture(household)

      assert Households.update_household(member_scope, %{name: "Hijacked"}) ==
               {:error, :unauthorized}

      assert Repo.get!(Household, household.id).name == "Original"
    end
  end

  describe "list_members/1" do
    test "lists the household's members, owner first" do
      owner = user_fixture(email: "zed@example.com")
      %{scope: scope, household: household} = household_fixture(owner)
      %{user: member} = member_fixture(household)
      household_fixture()

      assert Enum.map(Households.list_members(scope), & &1.id) == [owner.id, member.id]
    end
  end

  describe "list_meal_slots/1" do
    test "only lists the scope's household's active slots" do
      %{scope: scope, household: household} = household_fixture()
      %{scope: other_scope} = household_fixture()

      archived = Repo.get_by!(MealSlot, household_id: household.id, default_key: "snack")
      Repo.update!(Ecto.Changeset.change(archived, archived_at: DateTime.utc_now(:second)))

      assert Enum.map(Households.list_meal_slots(scope), & &1.name) == [
               "Breakfast",
               "Lunch",
               "Dinner"
             ]

      assert length(Households.list_meal_slots(other_scope)) == 4
    end
  end

  describe "meal slot constraints" do
    test "names are unique per household, ignoring case, among active slots" do
      %{household: household} = household_fixture()
      %{household: other} = household_fixture()

      assert_raise Ecto.ConstraintError, ~r/meal_slots_household_id_name_index/, fn ->
        Repo.insert!(%MealSlot{household_id: household.id, name: "DINNER", position: 9})
      end

      assert %MealSlot{} =
               Repo.insert!(%MealSlot{household_id: other.id, name: "Pudding", position: 9})
    end

    test "default_key must be one of the defaults" do
      %{household: household} = household_fixture()

      assert_raise Ecto.ConstraintError, ~r/default_key_valid/, fn ->
        Repo.insert!(%MealSlot{
          household_id: household.id,
          name: "Brunch",
          position: 9,
          default_key: "brunch"
        })
      end
    end
  end

  describe "subscribe/1 and broadcast/2" do
    test "deliver messages to the same household only" do
      %{scope: scope} = household_fixture()
      %{scope: other_scope} = household_fixture()

      :ok = Households.subscribe(scope)
      :ok = Households.broadcast(scope, {:household_changed, :test})
      :ok = Households.broadcast(other_scope, {:household_changed, :other})

      assert_receive {:household_changed, :test}
      refute_receive {:household_changed, :other}
    end
  end

  describe "the session scope" do
    test "includes the user's household" do
      %{user: user, household: household} = household_fixture()
      token = Accounts.generate_user_session_token(user)

      {session_user, _} = Accounts.get_user_by_session_token(token)
      assert %Scope{household: %Household{id: id}} = Scope.for_user(session_user)
      assert id == household.id
    end

    test "has no household for a user without one" do
      token = Accounts.generate_user_session_token(user_fixture())

      {session_user, _} = Accounts.get_user_by_session_token(token)
      assert %Scope{household: nil} = Scope.for_user(session_user)
    end
  end
end
