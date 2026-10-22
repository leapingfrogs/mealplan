defmodule MealplanWeb.PlanLive.SlotMealsTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning

  setup :register_and_log_in_user_with_household

  setup %{conn: conn, scope: scope} do
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    soup = recipe_fixture(scope, %{name: "Soup", servings: 6})
    chilli_night = meal_fixture(scope, %{name: "Chilli night"})
    {:ok, _meal} = Meals.set_slots(scope, chilli_night.id, [slots["dinner"].id])
    eat_out = meal_fixture(scope, %{name: "Eat out"})
    monday = Planning.current_week(scope)
    {:ok, view, _html} = live(conn, "/plan/#{monday}")

    %{
      view: view,
      slots: slots,
      soup: soup,
      chilli_night: chilli_night,
      eat_out: eat_out,
      monday: monday
    }
  end

  defp open_add(view, date, slot) do
    view |> element("#cell-#{date}-#{slot.id} button", "Add") |> render_click()
  end

  defp open?(view, section), do: has_element?(view, "##{section} > button[aria-expanded=true]")

  defp slot_names(scope, meal_id),
    do: scope |> Meals.get_meal!(meal_id) |> Map.fetch!(:slots) |> Enum.map(& &1.name)

  test "lists the slot's meals first and open, other meals and recipes collapsed", c do
    open_add(c.view, c.monday, c.slots["dinner"])

    assert has_element?(c.view, "#slot-meals", "Meals for Dinner")
    assert has_element?(c.view, "#slot-meals #pick-meal-#{c.chilli_night.id}")
    assert has_element?(c.view, "#other-meals #pick-meal-#{c.eat_out.id}")
    assert has_element?(c.view, "#recipe-choices #pick-recipe-#{c.soup.id}")
    assert open?(c.view, "slot-meals")
    refute open?(c.view, "other-meals")
    refute open?(c.view, "recipe-choices")
    assert has_element?(c.view, "#other-meals-body.hidden")
  end

  test "a section opens and closes when tapped", c do
    open_add(c.view, c.monday, c.slots["dinner"])

    c.view |> element("#other-meals > button") |> render_click()
    assert open?(c.view, "other-meals")
    refute has_element?(c.view, "#other-meals-body.hidden")

    c.view |> element("#slot-meals > button") |> render_click()
    refute open?(c.view, "slot-meals")

    c.view |> element("#other-meals > button") |> render_click()
    refute open?(c.view, "other-meals")
  end

  test "searching opens the sections with matches", c do
    open_add(c.view, c.monday, c.slots["dinner"])

    c.view |> form("#sheet-search", %{q: "ou"}) |> render_change()
    assert open?(c.view, "other-meals")
    assert open?(c.view, "recipe-choices")
    assert has_element?(c.view, "#slot-meals", "No Dinner meals match")
    refute has_element?(c.view, "#pick-meal-#{c.chilli_night.id}")
  end

  test "says when no meals are tagged for the slot", c do
    open_add(c.view, c.monday, c.slots["lunch"])

    assert has_element?(c.view, "#slot-meals", "No meals tagged for Lunch yet")
    assert has_element?(c.view, "#other-meals #pick-meal-#{c.chilli_night.id}")
  end

  test "planning a new meal or a recipe tags it with the slot", c do
    open_add(c.view, c.monday, c.slots["lunch"])
    c.view |> form("#sheet-search", %{q: "Takeaway"}) |> render_change()
    c.view |> element("#pick-new") |> render_click()

    open_add(c.view, c.monday, c.slots["lunch"])
    c.view |> element("#pick-recipe-#{c.soup.id} button") |> render_click()

    meals = Map.new(Meals.list_meals(c.scope), &{&1.name, &1.id})
    assert slot_names(c.scope, meals["Takeaway"]) == ["Lunch"]
    assert slot_names(c.scope, meals["Soup"]) == ["Lunch"]

    open_add(c.view, Date.add(c.monday, 1), c.slots["lunch"])
    assert has_element?(c.view, "#slot-meals #pick-meal-#{meals["Takeaway"]}")
  end

  test "picking an existing meal adds the slot to its tags", c do
    open_add(c.view, c.monday, c.slots["lunch"])
    c.view |> element("#pick-meal-#{c.eat_out.id} button") |> render_click()

    open_add(c.view, c.monday, c.slots["lunch"])
    c.view |> element("#pick-meal-#{c.chilli_night.id} button") |> render_click()

    open_add(c.view, c.monday, c.slots["dinner"])
    c.view |> element("#pick-meal-#{c.chilli_night.id} button") |> render_click()

    assert slot_names(c.scope, c.eat_out.id) == ["Lunch"]
    assert slot_names(c.scope, c.chilli_night.id) == ["Lunch", "Dinner"]
  end

  test "changing a planned meal lists that slot's meals first, and tags the new one", c do
    {:ok, planned} =
      Planning.plan_meal(c.scope, c.monday, c.slots["dinner"].id, c.eat_out.id, 4)

    {:ok, view, _html} = live(c.conn, "/plan/#{c.monday}")
    view |> element("#planned-#{planned.id} button") |> render_click()

    assert has_element?(view, "#slot-meals #pick-meal-#{c.chilli_night.id}")
    refute has_element?(view, "#recipe-choices")

    view |> element("#other-meals > button") |> render_click()
    view |> element("#pick-meal-#{c.eat_out.id} button") |> render_click()
    assert slot_names(c.scope, c.eat_out.id) == ["Dinner"]
  end
end
