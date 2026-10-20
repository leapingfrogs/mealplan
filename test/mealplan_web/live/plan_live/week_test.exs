defmodule MealplanWeb.PlanLive.WeekTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning

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

    setup %{scope: scope} do
      slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
      chilli = recipe_fixture(scope, %{name: "Chilli", servings: 4})

      %{
        slots: slots,
        chilli: chilli,
        meal: meal_fixture(scope, %{name: "Chilli night"}, [chilli]),
        today: Planning.today(scope),
        this_week: Planning.current_week(scope)
      }
    end

    test "opens on this week with the days, slots and progress",
         %{conn: conn, scope: scope, slots: slots, meal: meal, today: today, this_week: monday} do
      {:ok, _} = Planning.plan_meal(scope, today, slots["dinner"].id, meal.id, 5)

      {:ok, view, _html} = live(conn, ~p"/plan")

      assert has_element?(view, "#week-title", "This week")

      for day <- Date.range(monday, Date.add(monday, 6)),
          do: assert(has_element?(view, "#day-#{day}"))

      assert has_element?(view, "#day-#{today}", "Today")
      assert has_element?(view, "#cell-#{today}-#{slots["breakfast"].id}", "Breakfast")
      assert has_element?(view, "#cell-#{today}-#{slots["dinner"].id}", "Chilli night")
      assert has_element?(view, "#cell-#{today}-#{slots["dinner"].id}", "×5")
      assert has_element?(view, "#week-progress", "1 of 28")
    end

    test "shows only the household's own plans", %{conn: conn, today: today} do
      %{scope: other_scope} = household_fixture()
      [slot | _] = Households.list_meal_slots(other_scope)

      {:ok, _} =
        Planning.plan_meal(
          other_scope,
          today,
          slot.id,
          meal_fixture(other_scope, %{name: "Theirs"}).id
        )

      {:ok, view, _html} = live(conn, ~p"/plan")
      refute render(view) =~ "Theirs"
    end

    test "moves between weeks and normalises dates to Mondays", %{conn: conn, this_week: monday} do
      {:ok, view, _html} = live(conn, ~p"/plan")

      view |> element("#next-week") |> render_click()
      next = Date.add(monday, 7)
      assert_patch(view, "/plan/#{next}")
      assert has_element?(view, "#week-title", "Next week")
      assert has_element?(view, "#day-#{next}")

      view |> element("#this-week") |> render_click()
      assert_patch(view, "/plan/#{monday}")
      assert has_element?(view, "#week-title", "This week")
      refute has_element?(view, "#this-week")

      view |> element("#previous-week") |> render_click()
      assert has_element?(view, "#week-title", "Last week")

      assert {:error, {:live_redirect, %{to: "/plan/2029-12-31"}}} =
               live(conn, "/plan/2030-01-02")

      {:ok, far, _html} = live(conn, "/plan/2029-12-31")
      assert has_element?(far, "#week-title", "Week of 31 December")
    end

    test "an unknown date goes back to the default week", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/plan", flash: %{"error" => error}}}} =
               live(conn, "/plan/not-a-date")

      assert error =~ "recognise"
    end

    test "opens on next week once this week is fully planned",
         %{conn: conn, scope: scope, slots: slots, this_week: monday} do
      for day <- Date.range(monday, Date.add(monday, 6)), {_key, slot} <- slots do
        {:ok, _} = Planning.skip_slot(scope, day, slot.id)
      end

      {:ok, view, _html} = live(conn, ~p"/plan")
      assert has_element?(view, "#week-title", "Next week")

      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      assert has_element?(view, "#week-progress", "All planned")
    end

    test "skips and unskips a slot", %{conn: conn, scope: scope, slots: slots, today: today} do
      {:ok, view, _html} = live(conn, ~p"/plan")
      cell = "#cell-#{today}-#{slots["lunch"].id}"

      view |> element("#{cell} button", "Skip") |> render_click()
      assert has_element?(view, cell, "Skipped")
      assert has_element?(view, "#week-progress", "1 of 28")
      assert [_] = Planning.get_week(scope, today).skips

      view |> element("#{cell} button", "Undo") |> render_click()
      refute has_element?(view, cell, "Skipped")
      assert has_element?(view, "#week-progress", "0 of 28")
    end

    test "a slot that gained a meal meanwhile can't be skipped",
         %{conn: conn, scope: scope, slots: slots, meal: meal, today: today} do
      {:ok, view, _html} = live(conn, ~p"/plan")
      {:ok, _} = Planning.plan_meal(scope, today, slots["lunch"].id, meal.id)

      html =
        render_click(view, "skip", %{
          "date" => Date.to_iso8601(today),
          "slot" => slots["lunch"].id
        })

      assert html =~ "Couldn&#39;t skip that slot"
      assert has_element?(view, "#cell-#{today}-#{slots["lunch"].id}", "Chilli night")
    end

    test "marks leftovers with where they came from",
         %{conn: conn, scope: scope, slots: slots, meal: meal, chilli: chilli, this_week: monday} do
      {:ok, source} = Planning.plan_meal(scope, monday, slots["dinner"].id, meal.id)
      {:ok, eater} = Planning.plan_meal(scope, Date.add(monday, 2), slots["lunch"].id, meal.id)
      {:ok, _} = Planning.add_leftover(scope, eater.id, source.id, chilli.id)

      {:ok, view, _html} = live(conn, "/plan/#{monday}")

      assert has_element?(view, "#planned-#{eater.id} .leftovers")
      refute has_element?(view, "#planned-#{source.id} .leftovers")

      assert has_element?(
               view,
               "#planned-#{eater.id} .leftovers[title='Leftovers from #{Calendar.strftime(monday, "%a %-d %b")}']"
             )
    end

    test "follows other members' changes live",
         %{conn: conn, scope: scope, slots: slots, meal: meal, today: today} do
      {:ok, view, _html} = live(conn, ~p"/plan")
      %{scope: member_scope} = member_fixture(scope.household)

      {:ok, planned_meal} =
        Planning.plan_meal(member_scope, today, slots["breakfast"].id, meal.id)

      assert has_element?(view, "#planned-#{planned_meal.id}", "Chilli night")

      {:ok, _} = Meals.rename_meal(member_scope, meal.id, %{name: "Chilli con carne"})
      assert has_element?(view, "#planned-#{planned_meal.id}", "Chilli con carne")

      {:ok, _} = Planning.skip_slot(member_scope, today, slots["snack"].id)
      assert has_element?(view, "#cell-#{today}-#{slots["snack"].id}", "Skipped")

      {:ok, _} = Households.rename_meal_slot(scope, slots["lunch"].id, %{name: "Midday"})
      assert has_element?(view, "#cell-#{today}-#{slots["lunch"].id}", "Midday")

      {:ok, _} = Households.update_household(scope, %{time_zone: "Pacific/Kiritimati"})
      assert has_element?(view, "#days")
    end

    test "copies last week into this one, once",
         %{conn: conn, scope: scope, slots: slots, meal: meal, this_week: monday} do
      last_monday = Date.add(monday, -7)
      {:ok, _} = Planning.plan_meal(scope, last_monday, slots["dinner"].id, meal.id, 3)
      {:ok, _} = Planning.skip_slot(scope, Date.add(last_monday, 1), slots["lunch"].id)
      {:ok, view, _html} = live(conn, "/plan/#{monday}")

      html = view |> element("#copy-last-week") |> render_click()
      assert html =~ "Copied 1 meal and 1 skipped slot from last week."
      assert has_element?(view, "#cell-#{monday}-#{slots["dinner"].id}", "Chilli night")
      assert has_element?(view, "#cell-#{monday}-#{slots["dinner"].id}", "×3")
      assert has_element?(view, "#cell-#{Date.add(monday, 1)}-#{slots["lunch"].id}", "Skipped")

      html = view |> element("#copy-last-week") |> render_click()
      assert html =~ "Nothing to copy"
      assert length(Planning.get_week(scope, monday).planned_meals) == 1
    end

    test "copying is offered only while the week has empty slots",
         %{conn: conn, scope: scope, slots: slots, this_week: monday} do
      for day <- Date.range(monday, Date.add(monday, 6)), {_key, slot} <- slots do
        {:ok, _} = Planning.skip_slot(scope, day, slot.id)
      end

      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      refute has_element?(view, "#copy-last-week")
    end

    test "a household without slots is told where to add them", %{conn: conn, scope: scope} do
      Mealplan.Repo.delete_all(Mealplan.Households.MealSlot)
      {:ok, view, _html} = live(conn, ~p"/plan")
      assert render(view) =~ "no meal slots"
      assert has_element?(view, "#week-progress", "0 of 0")
      _ = scope
    end
  end
end
