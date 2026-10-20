defmodule MealplanWeb.PlanLive.PlannedMealsTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Repo

  setup :register_and_log_in_user_with_household

  setup %{conn: conn, scope: scope} do
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    chilli = recipe_fixture(scope, %{name: "Chilli", servings: 4})
    soup = recipe_fixture(scope, %{name: "Soup", servings: 6})
    monday = Planning.current_week(scope)
    {:ok, view, _html} = live(conn, "/plan/#{monday}")

    %{
      view: view,
      slots: slots,
      chilli: chilli,
      soup: soup,
      chilli_night: meal_fixture(scope, %{name: "Chilli night"}, [chilli]),
      eat_out: meal_fixture(scope, %{name: "Eat out"}),
      monday: monday
    }
  end

  defp open_add(view, date, slot) do
    view |> element("#cell-#{date}-#{slot.id} button", "Add") |> render_click()
    assert has_element?(view, "#plan-sheet")
  end

  defp planned(scope, date), do: Planning.get_week(scope, date).planned_meals

  describe "adding" do
    test "plans a meal with the household's usual servings, adjustable first",
         %{view: view, scope: scope, slots: slots, monday: monday} = c do
      open_add(view, monday, slots["dinner"])
      assert has_element?(view, "#plan-sheet", "Add to Dinner on")
      assert has_element?(view, "#add-servings", "#{scope.household.usually_feeding}")

      view |> element("#add-servings button[phx-value-delta='1']") |> render_click()
      view |> element("#pick-meal-#{c.chilli_night.id} button") |> render_click()

      refute has_element?(view, "#plan-sheet")
      assert [%PlannedMeal{meal_id: meal_id, servings: servings}] = planned(scope, monday)
      assert {meal_id, servings} == {c.chilli_night.id, scope.household.usually_feeding + 1}
      assert has_element?(view, "#cell-#{monday}-#{slots["dinner"].id}", "Chilli night")
    end

    test "a slot can hold several meals",
         %{view: view, scope: scope, slots: slots, monday: monday} = c do
      open_add(view, monday, slots["dinner"])
      view |> element("#pick-meal-#{c.chilli_night.id} button") |> render_click()
      open_add(view, monday, slots["dinner"])
      view |> element("#pick-meal-#{c.eat_out.id} button") |> render_click()

      assert [first, second] = planned(scope, monday)
      assert {first.meal_id, second.meal_id} == {c.chilli_night.id, c.eat_out.id}
      cell = "#cell-#{monday}-#{slots["dinner"].id}"
      assert has_element?(view, "#{cell} #planned-#{first.id}")
      assert has_element?(view, "#{cell} #planned-#{second.id}")
      refute has_element?(view, "#{cell} button", "Skip")
    end

    test "searches, and plans a recipe directly as its one-recipe meal",
         %{view: view, scope: scope, slots: slots, monday: monday, soup: soup} do
      open_add(view, monday, slots["lunch"])

      view |> form("#sheet-search", %{q: "sou"}) |> render_change()
      refute has_element?(view, "#sheet-results", "Chilli night")
      view |> element("#pick-recipe-#{soup.id} button") |> render_click()

      [planned_meal] = planned(scope, monday)
      meal = Meals.get_meal!(scope, planned_meal.meal_id)
      assert meal.name == "Soup"
      assert [%{recipe_id: recipe_id}] = meal.meal_recipes
      assert recipe_id == soup.id

      # The second time reuses the same meal.
      tuesday = Date.add(monday, 1)
      open_add(view, tuesday, slots["lunch"])
      view |> element("#pick-recipe-#{soup.id} button") |> render_click()

      assert [%{meal_id: same_meal}] = Enum.filter(planned(scope, monday), &(&1.date == tuesday))
      assert same_meal == meal.id
    end

    test "creates a meal from the search text", %{
      view: view,
      scope: scope,
      slots: slots,
      monday: monday
    } do
      open_add(view, monday, slots["dinner"])

      view |> form("#sheet-search", %{q: "Takeaway"}) |> render_change()
      view |> element("#pick-new button") |> render_click()

      [planned_meal] = planned(scope, monday)
      assert Meals.get_meal!(scope, planned_meal.meal_id).name == "Takeaway"

      open_add(view, monday, slots["lunch"])
      view |> form("#sheet-search", %{q: "takeaway"}) |> render_change()
      refute has_element?(view, "#pick-new")
    end

    test "closes without planning", %{view: view, scope: scope, slots: slots, monday: monday} do
      open_add(view, monday, slots["dinner"])
      view |> element("#plan-sheet button[aria-label=Close]") |> render_click()
      refute has_element?(view, "#plan-sheet")

      open_add(view, monday, slots["dinner"])
      render_keydown(view, "close_sheet", %{"key" => "Escape"})
      refute has_element?(view, "#plan-sheet")
      assert planned(scope, monday) == []
    end
  end

  describe "editing" do
    setup %{scope: scope, slots: slots, monday: monday, chilli_night: meal} do
      {:ok, planned_meal} = Planning.plan_meal(scope, monday, slots["dinner"].id, meal.id, 4)
      %{planned_meal: planned_meal}
    end

    defp open_edit(view, planned_meal) do
      view |> element("#planned-#{planned_meal.id} button") |> render_click()
      assert has_element?(view, "#plan-sheet", "Chilli night")
    end

    test "changes servings", %{
      conn: conn,
      scope: scope,
      planned_meal: planned_meal,
      monday: monday
    } do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      open_edit(view, planned_meal)

      view |> element("#edit-servings button[phx-value-delta='1']") |> render_click()
      view |> element("#edit-servings button[phx-value-delta='1']") |> render_click()
      view |> element("#edit-servings button[phx-value-delta='-1']") |> render_click()

      assert Repo.reload!(planned_meal).servings == 5
      assert has_element?(view, "#edit-servings", "5")
      assert has_element?(view, "#planned-#{planned_meal.id}", "×5")
      _ = scope
    end

    test "changes the meal", %{
      conn: conn,
      planned_meal: planned_meal,
      monday: monday,
      eat_out: eat_out
    } do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      open_edit(view, planned_meal)

      view |> element("#change-meal #pick-meal-#{eat_out.id} button") |> render_click()

      assert Repo.reload!(planned_meal).meal_id == eat_out.id
      assert has_element?(view, "#planned-#{planned_meal.id}", "Eat out")
      refute has_element?(view, "#plan-sheet")
    end

    test "moves to another day and slot", %{
      conn: conn,
      planned_meal: planned_meal,
      monday: monday,
      slots: slots
    } do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      open_edit(view, planned_meal)
      wednesday = Date.add(monday, 2)

      html =
        view
        |> form("#move-form", move: %{date: Date.to_iso8601(wednesday), slot: slots["lunch"].id})
        |> render_submit()

      assert html =~ "Moved to #{Calendar.strftime(wednesday, "%a %-d %b")}, Lunch"
      assert %{date: ^wednesday} = Repo.reload!(planned_meal)

      assert has_element?(
               view,
               "#cell-#{wednesday}-#{slots["lunch"].id} #planned-#{planned_meal.id}"
             )

      refute has_element?(
               view,
               "#cell-#{monday}-#{slots["dinner"].id} #planned-#{planned_meal.id}"
             )
    end

    test "removes", %{conn: conn, planned_meal: planned_meal, monday: monday} do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      open_edit(view, planned_meal)

      view |> element("#remove-planned-meal") |> render_click()

      refute Repo.get(PlannedMeal, planned_meal.id)
      refute has_element?(view, "#planned-#{planned_meal.id}")
      refute has_element?(view, "#plan-sheet")
    end

    test "the sheet closes if another member removes the meal",
         %{conn: conn, scope: scope, planned_meal: planned_meal, monday: monday} do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      open_edit(view, planned_meal)

      %{scope: member_scope} = member_fixture(scope.household)
      {:ok, _} = Planning.remove_planned_meal(member_scope, planned_meal.id)

      refute has_element?(view, "#plan-sheet")
      assert render_click(view, "remove", %{}) =~ "Plan"
    end

    test "shows where leftovers come from",
         %{conn: conn, scope: scope, planned_meal: source, monday: monday, slots: slots} = c do
      {:ok, eater} =
        Planning.plan_meal(scope, Date.add(monday, 2), slots["lunch"].id, c.chilli_night.id)

      {:ok, _} = Planning.add_leftover(scope, eater.id, source.id, c.chilli.id)
      {:ok, view, _html} = live(conn, "/plan/#{monday}")

      view |> element("#planned-#{eater.id} button") |> render_click()

      assert has_element?(
               view,
               "#sheet-recipe-#{c.chilli.id}",
               "Leftovers from #{Calendar.strftime(monday, "%a %-d %b")} dinner"
             )
    end

    test "a stale chip reloads the week", %{
      conn: conn,
      scope: scope,
      planned_meal: planned_meal,
      monday: monday
    } do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      Repo.delete!(planned_meal)

      render_click(view, "edit", %{"id" => planned_meal.id})
      refute has_element?(view, "#planned-#{planned_meal.id}")
      refute has_element?(view, "#plan-sheet")
      _ = scope
    end
  end

  test "a failed change is reported", %{
    view: view,
    slots: slots,
    monday: monday,
    chilli_night: meal
  } do
    open_add(view, monday, slots["dinner"])
    Repo.delete!(Repo.get!(Mealplan.Meals.Meal, meal.id))

    html = view |> element("#pick-meal-#{meal.id} button") |> render_click()
    assert html =~ "Couldn&#39;t change the plan"
  end

  test "another household's slot can't be added to", %{view: view, monday: monday} do
    %{scope: other_scope} = household_fixture()
    [their_slot | _] = Households.list_meal_slots(other_scope)

    render_click(view, "add", %{"date" => Date.to_iso8601(monday), "slot" => their_slot.id})
    refute has_element?(view, "#plan-sheet")
  end
end
