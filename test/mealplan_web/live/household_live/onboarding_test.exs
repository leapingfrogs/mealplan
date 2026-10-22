defmodule MealplanWeb.HouseholdLive.OnboardingTest do
  use MealplanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mealplan.Households.Household
  alias Mealplan.Repo

  test "requires a login", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/welcome")
    assert path == ~p"/users/log-in"
  end

  describe "without a household" do
    setup :register_and_log_in_user

    test "shows the household form with the default slots", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/welcome")

      assert has_element?(view, "#household-form")
      assert has_element?(view, "#default-slots-note", "Breakfast, Lunch, Dinner and Snack")
      # The invite field keeps its full-width textarea styling.
      assert has_element?(view, "textarea#invites.textarea.w-full")
      assert has_element?(view, "#household-form button.btn.btn-primary", "Create household")
    end

    test "creates the household and goes to the week plan", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/welcome")

      render_change(view, "validate", %{"household" => %{"time_zone" => "Europe/London"}})
      assert has_element?(view, "#time-zone-note", "Europe/London")

      view
      |> element("#household_usually_feeding-stepper button[aria-label='Fewer people']")
      |> render_click()

      assert has_element?(view, "#household_usually_feeding-stepper output", "3")

      assert {:error, {:redirect, %{to: path}}} =
               view
               |> form("#household-form", household: %{name: "The Davies household"})
               |> render_submit(%{"household" => %{"time_zone" => "Europe/London"}})

      assert path == ~p"/plan"
      household = Repo.get_by!(Household, owner_id: user.id)

      assert %{name: "The Davies household", usually_feeding: 3, time_zone: "Europe/London"} =
               household

      {:ok, plan, _html} = live(conn, ~p"/plan")
      assert has_element?(plan, "#household-name", "The Davies household")
    end

    test "falls back to UTC when the browser reports no time zone", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/welcome")

      view
      |> form("#household-form", household: %{name: "No zone"})
      |> render_submit()

      assert Repo.get_by!(Household, owner_id: user.id).time_zone == "Etc/UTC"
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/welcome")

      html =
        view
        |> form("#household-form", household: %{name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"

      html =
        view
        |> form("#household-form", household: %{name: "Zoned"})
        |> render_submit(%{"household" => %{"time_zone" => "Mars/Olympus"}})

      assert html =~ "Time zone is not a known time zone"
    end
  end

  test "sends users who already have a household to the plan", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user_with_household(%{conn: conn})

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/welcome")
    assert path == ~p"/plan"
  end
end
