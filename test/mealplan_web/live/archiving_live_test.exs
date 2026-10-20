defmodule MealplanWeb.ArchivingLiveTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Recipes
  alias Mealplan.Repo

  setup :register_and_log_in_user_with_household

  setup %{scope: scope} do
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    chilli = recipe_fixture(scope, %{name: "Chilli"})
    today = Planning.today(scope)

    %{
      slots: slots,
      chilli: chilli,
      meal: meal_fixture(scope, %{name: "Chilli night"}, [chilli]),
      past: Date.add(today, -3),
      future: Date.add(today, 2)
    }
  end

  defp plan(scope, date, slot, meal) do
    {:ok, planned_meal} = Planning.plan_meal(scope, date, slot.id, meal.id, 2)
    planned_meal
  end

  describe "recipes" do
    test "deleting lists its meals, then deletes", %{conn: conn, chilli: chilli} do
      {:ok, view, _html} = live(conn, ~p"/recipes/#{chilli}")

      view |> element("#delete-recipe") |> render_click()
      assert has_element?(view, "#delete-recipe-panel", "taken out of Chilli night")
      assert has_element?(view, "#confirm-delete-recipe", "Delete recipe")

      view |> element("#delete-recipe-panel button", "Cancel") |> render_click()
      refute has_element?(view, "#delete-recipe-panel")

      view |> element("#delete-recipe") |> render_click()

      assert {:ok, _list, html} =
               view
               |> element("#confirm-delete-recipe")
               |> render_click()
               |> follow_redirect(conn)

      assert html =~ "Chilli deleted."
      refute Repo.get(Mealplan.Recipes.Recipe, chilli.id)
    end

    test "one used by past plans is archived, listed and restored",
         %{conn: conn, scope: scope, chilli: chilli, meal: meal, past: past, slots: slots} do
      plan(scope, past, slots["dinner"], meal)
      {:ok, view, _html} = live(conn, ~p"/recipes/#{chilli}")

      view |> element("#delete-recipe") |> render_click()
      assert has_element?(view, "#delete-recipe-panel", "archived")

      {:ok, _list, html} =
        view
        |> element("#confirm-delete-recipe", "Archive recipe")
        |> render_click()
        |> follow_redirect(conn)

      assert html =~ "Chilli archived."

      {:ok, archived, _html} = live(conn, ~p"/recipes/archived")
      assert has_element?(archived, "#archived-#{chilli.id}", "Chilli")
      archived |> element("#archived-#{chilli.id} button", "Restore") |> render_click()
      refute has_element?(archived, "#archived-#{chilli.id}")
      assert has_element?(archived, "#no-archived")
      assert scope |> Recipes.list_recipes() |> Enum.any?(&(&1.id == chilli.id))
    end

    test "an archived recipe's page offers Restore",
         %{conn: conn, scope: scope, chilli: chilli} = c do
      plan(scope, c.past, c.slots["dinner"], c.meal)
      {:ok, :archived} = Recipes.delete_recipe(scope, chilli)
      {:ok, view, _html} = live(conn, ~p"/recipes/#{chilli}")

      assert has_element?(view, "#archived-badge")
      refute has_element?(view, "#edit-recipe")
      view |> element("#restore-recipe") |> render_click()
      refute has_element?(view, "#archived-badge")
    end

    test "an open recipe page leaves when another member deletes it",
         %{conn: conn, scope: scope, chilli: chilli} do
      {:ok, view, _html} = live(conn, ~p"/recipes/#{chilli}")
      {:ok, :deleted} = Recipes.delete_recipe(scope, chilli)
      assert_redirect(view, ~p"/recipes")
    end
  end

  describe "meals" do
    test "deleting lists the upcoming plans it removes",
         %{conn: conn, scope: scope, meal: meal, future: future, slots: slots} do
      upcoming = plan(scope, future, slots["dinner"], meal)
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")

      view |> element("#delete-meal") |> render_click()

      assert has_element?(
               view,
               "#delete-meal-panel",
               Calendar.strftime(future, "%a %-d %b") <> " dinner"
             )

      {:ok, _list, html} =
        view
        |> element("#confirm-delete-meal", "Delete meal")
        |> render_click()
        |> follow_redirect(conn)

      assert html =~ "Chilli night deleted."
      refute Repo.get(Mealplan.Planning.PlannedMeal, upcoming.id)
    end

    test "one planned before today is archived and can be restored",
         %{conn: conn, scope: scope, meal: meal} = c do
      plan(scope, c.past, c.slots["dinner"], meal)
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")
      view |> element("#delete-meal") |> render_click()
      view |> element("#delete-meal-panel button", "Cancel") |> render_click()
      view |> element("#delete-meal") |> render_click()

      {:ok, _list, _html} =
        view
        |> element("#confirm-delete-meal", "Archive meal")
        |> render_click()
        |> follow_redirect(conn)

      {:ok, page, _html} = live(conn, ~p"/meals/#{meal}")
      assert has_element?(page, "#archived-badge")
      refute has_element?(page, "#recipe-picker")

      {:ok, archived, _html} = live(conn, ~p"/meals/archived")
      {:ok, _} = Meals.create_meal(scope, %{name: "Chilli night"})
      html = archived |> element("#archived-#{meal.id} button", "Restore") |> render_click()
      assert html =~ "Another meal is already called Chilli night"

      html = page |> element("#restore-meal") |> render_click()
      assert html =~ "Another meal is already called Chilli night"
    end

    test "restores from the meal page", %{conn: conn, scope: scope, meal: meal} = c do
      plan(scope, c.past, c.slots["dinner"], meal)
      {:ok, :archived} = Meals.delete_meal(scope, meal)
      {:ok, page, _html} = live(conn, ~p"/meals/#{meal}")

      page |> element("#restore-meal") |> render_click()
      refute has_element?(page, "#archived-badge")
      assert has_element?(page, "#recipe-picker")
    end
  end

  describe "slots" do
    test "a slot with upcoming meals asks where they go",
         %{conn: conn, scope: scope, meal: meal, future: future, slots: slots} do
      upcoming = plan(scope, future, slots["snack"], meal)
      {:ok, view, _html} = live(conn, ~p"/household")

      view |> element("#slot-#{slots["snack"].id} button", "Delete") |> render_click()
      assert has_element?(view, "#delete-slot-panel", "Chilli night")

      view |> element("#delete-slot-panel button", "Cancel") |> render_click()
      refute has_element?(view, "#delete-slot-panel")

      view |> element("#slot-#{slots["snack"].id} button", "Delete") |> render_click()
      html = view |> form("#delete-slot-form", %{upcoming: slots["lunch"].id}) |> render_submit()

      assert html =~ "Snack deleted."
      assert Repo.reload!(upcoming).meal_slot_id == slots["lunch"].id
    end

    test "one used by past plans is archived and still shown in that week",
         %{conn: conn, scope: scope, meal: meal, past: past, slots: slots} do
      plan(scope, past, slots["snack"], meal)
      {:ok, view, _html} = live(conn, ~p"/household")

      html = view |> element("#slot-#{slots["snack"].id} button", "Delete") |> render_click()
      assert html =~ "Snack removed. Past weeks still show it."

      {:ok, week, _html} = live(conn, "/plan/#{Planning.week_start(past)}")
      assert has_element?(week, "#cell-#{past}-#{slots["snack"].id}", "(removed)")
      assert has_element?(week, "#cell-#{past}-#{slots["snack"].id}", "Chilli night")
      refute has_element?(week, "#cell-#{past}-#{slots["snack"].id} button", "Add")
      refute has_element?(week, "#cell-#{Date.add(past, 1)}-#{slots["snack"].id}")
    end
  end
end
