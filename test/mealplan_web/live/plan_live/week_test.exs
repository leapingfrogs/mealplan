defmodule MealplanWeb.PlanLive.WeekTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Phoenix.LiveViewTest

  test "requires a login", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/plan")
    assert path == ~p"/users/log-in"
  end

  test "sends users without a household to /welcome", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/plan")
    assert path == ~p"/welcome"
  end

  describe "with a household" do
    setup :register_and_log_in_user_with_household

    test "shows the household and only its meal slots", %{conn: conn, household: household} do
      %{household: other} = household_fixture()

      {:ok, view, _html} = live(conn, ~p"/plan")

      assert has_element?(view, "#household-name", household.name)
      refute has_element?(view, "#household-name", other.name)

      slots = view |> element("#meal-slots") |> render()
      assert slots =~ "Breakfast"
      assert slots =~ "Snack"
      assert length(Regex.scan(~r/id="meal-slot-/, slots)) == 4
    end
  end
end
