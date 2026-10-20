defmodule MealplanWeb.HouseholdLive.SettingsTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Repo

  test "sends users without a household to /welcome", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/household")
    assert path == ~p"/welcome"
  end

  describe "as the owner" do
    setup :register_and_log_in_user_with_household

    test "shows the details form and the members", %{conn: conn, user: user, household: household} do
      %{user: member} = member_fixture(household)

      {:ok, view, _html} = live(conn, ~p"/household")

      assert has_element?(view, "#household-form")
      assert has_element?(view, "#member-#{user.id}", "(you)")
      assert has_element?(view, "#member-#{user.id} .badge", "owner")
      assert has_element?(view, "#member-#{member.id}", member.email)
      refute has_element?(view, "#member-#{member.id} .badge", "owner")
    end

    test "saves changes and updates the header", %{conn: conn, household: household} do
      {:ok, view, _html} = live(conn, ~p"/household")

      html =
        view
        |> form("#household-form",
          household: %{name: "The Renamed", usually_feeding: 5, time_zone: "Europe/Paris"}
        )
        |> render_submit()

      assert html =~ "Household updated."

      assert %{name: "The Renamed", usually_feeding: 5, time_zone: "Europe/Paris"} =
               Repo.get!(Household, household.id)

      assert has_element?(view, "#household-name", "The Renamed")
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/household")

      html =
        view
        |> form("#household-form", household: %{name: "", time_zone: "Mars/Olympus"})
        |> render_change()

      assert html =~ "can&#39;t be blank"
      assert html =~ "is not a known time zone"
    end
  end

  describe "as a member" do
    setup %{conn: conn} do
      %{household: household, scope: owner_scope} = household_fixture()
      %{user: member} = member_fixture(household)
      %{conn: log_in_user(conn, member), household: household, owner_scope: owner_scope}
    end

    test "shows the details read-only", %{conn: conn, household: household} do
      {:ok, view, _html} = live(conn, ~p"/household")

      refute has_element?(view, "#household-form")
      assert has_element?(view, "#usually-feeding", to_string(household.usually_feeding))
      assert has_element?(view, "#time-zone", household.time_zone)
    end

    test "sees the owner's changes live", %{conn: conn, owner_scope: owner_scope} do
      {:ok, settings, _html} = live(conn, ~p"/household")
      {:ok, plan, _html} = live(conn, ~p"/plan")

      {:ok, _} =
        Households.update_household(owner_scope, %{name: "Live Name", usually_feeding: 7})

      assert has_element?(settings, "#household-name", "Live Name")
      assert has_element?(settings, "#usually-feeding", "7")
      assert has_element?(plan, "#household-name", "Live Name")
    end
  end

  test "pages without a message handler ignore other household events", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user_with_household(%{conn: conn})
    {:ok, plan, _html} = live(conn, ~p"/plan")

    :ok = Households.broadcast(scope, {:something_else, :happened})

    assert render(plan) =~ "meal-slots"
  end
end
