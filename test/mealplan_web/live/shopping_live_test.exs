defmodule MealplanWeb.ShoppingLiveTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Planning
  alias Mealplan.Shopping
  alias MealplanWeb.ShoppingLive.Index

  setup :register_and_log_in_user_with_household

  setup %{scope: scope} do
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    today = Planning.today(scope)

    chilli =
      recipe_fixture(scope, %{
        name: "Chilli",
        servings: 4,
        source: "Fry @onion{1} in @olive oil{2%tbsp} with @salt{}. Add @kidney beans{400%g}."
      })

    meal = meal_fixture(scope, %{name: "Chilli night"}, [chilli])
    {:ok, planned} = Planning.plan_meal(scope, today, slots["dinner"].id, meal.id, 4)
    %{slots: slots, today: today, meal: meal, planned: planned}
  end

  defp line(key), do: "#" <> Index.line_id(key)

  test "lists what to buy, and ticks and unticks lines", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/shopping")

    assert has_element?(view, "#change-range", "Today")
    assert has_element?(view, "#to-buy " <> line("kidney bean"), "400 g")
    assert has_element?(view, "#to-buy " <> line("olive oil"), "2 tbsp")

    view |> element(line("onion") <> " button[phx-click=tick]") |> render_click()
    assert has_element?(view, "#ticked " <> line("onion"))
    refute has_element?(view, "#to-buy " <> line("onion"))

    view |> element(line("onion") <> " button[phx-click=untick]") |> render_click()
    assert has_element?(view, "#to-buy " <> line("onion"))
    refute has_element?(view, "#ticked")
  end

  test "another member's ticks and plan changes show straight away", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, ~p"/shopping")
    %{scope: member} = member_fixture(c.scope.household)

    {:ok, _} = Shopping.tick(member, "kidney bean")
    assert has_element?(view, "#ticked " <> line("kidney bean"))

    {:ok, _} = Planning.set_servings(member, c.planned.id, 6)
    assert has_element?(view, "#to-buy " <> line("kidney bean"), "200 g more since ticked")
  end

  test "a line opens to show where it comes from, and can become a staple", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/shopping")

    view |> element(line("kidney bean") <> " button[phx-click=toggle_line]") |> render_click()
    assert has_element?(view, line("kidney bean"), "Chilli · ")
    assert has_element?(view, line("kidney bean"), " dinner · 400 g")

    view |> element(line("kidney bean") <> " button[phx-click=make_staple]") |> render_click()
    refute has_element?(view, "#to-buy " <> line("kidney bean"))
    assert has_element?(view, "#staples", "Staples, not listed (1)")
    assert has_element?(view, "#staples-body.hidden")

    view |> element("#staples > button") |> render_click()
    refute has_element?(view, "#staples-body.hidden")
    view |> element("#staples button[phx-click=need_staple]") |> render_click()
    assert has_element?(view, "#added li[id^=item-]", "kidney beans")
  end

  test "manual items are added, ticked and removed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/shopping")

    view |> form("#item-form", item: %{text: ""}) |> render_submit()
    assert has_element?(view, "#item-form", "can't be blank")

    view |> form("#item-form", item: %{text: "Kitchen roll"}) |> render_change()
    assert has_element?(view, "#item-form input[value='Kitchen roll']")
    view |> form("#item-form", item: %{text: "Kitchen roll"}) |> render_submit()
    assert has_element?(view, "#added li[id^=item-]", "Kitchen roll")
    refute has_element?(view, "#item-form input[value='Kitchen roll']")

    view |> element("#added li[id^=item-] button[phx-click=tick_item]") |> render_click()
    assert has_element?(view, "#ticked li[id^=item-]", "Kitchen roll")

    view |> element("#ticked li[id^=item-] button[phx-click=tick_item]") |> render_click()
    view |> element("#added li[id^=item-] button[phx-click=remove_item]") |> render_click()
    refute has_element?(view, "li[id^=item-]")
  end

  test "the ticked group collapses once it grows, and can be opened", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/shopping")

    for key <- ["onion", "olive oil", "salt"],
        do: view |> element(line(key) <> " button[phx-click=tick]") |> render_click()

    refute has_element?(view, "#ticked-body.hidden")
    view |> element(line("kidney bean") <> " button[phx-click=tick]") |> render_click()
    assert has_element?(view, "#ticked-body.hidden")
    assert has_element?(view, "#nothing-to-buy", "All done.")

    view |> element("#ticked > button") |> render_click()
    refute has_element?(view, "#ticked-body.hidden")
    view |> element("#ticked > button") |> render_click()
    assert has_element?(view, "#ticked-body.hidden")
  end

  test "the range changes by preset or dates, and says when nothing's planned",
       %{conn: conn, today: today} do
    {:ok, view, _html} = live(conn, ~p"/shopping")

    view |> element("#change-range") |> render_click()
    view |> element("#range-form button", "Next week") |> render_click()
    refute has_element?(view, "#range-form")
    assert has_element?(view, "#nothing-to-buy", "Plan some meals")

    view |> element("#change-range") |> render_click()
    view |> element("#range-form button", "This week") |> render_click()
    assert has_element?(view, "#to-buy " <> line("onion"))

    view |> element("#change-range") |> render_click()

    view
    |> form("#range-form", shopping_list: %{starts_on: today, ends_on: Date.add(today, 20)})
    |> render_submit()

    assert has_element?(view, "#range-form", "is more than 14 days on")
    view |> element("#range-form button", "Cancel") |> render_click()
    refute has_element?(view, "#range-form")

    tomorrow = Date.add(today, 1)
    view |> element("#change-range") |> render_click()

    view
    |> form("#range-form", shopping_list: %{starts_on: tomorrow, ends_on: tomorrow})
    |> render_submit()

    assert has_element?(view, "#change-range", Calendar.strftime(tomorrow, "%a %-d %b"))
  end

  test "starting a new list asks first, then clears ticks", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/shopping")
    view |> element(line("onion") <> " button[phx-click=tick]") |> render_click()

    view |> element("#start-new") |> render_click()
    assert has_element?(view, "#start-new-panel")
    view |> element("#start-new-panel button", "Cancel") |> render_click()
    refute has_element?(view, "#start-new-panel")

    view |> element("#start-new") |> render_click()
    view |> element("#confirm-start-new") |> render_click()
    refute has_element?(view, "#ticked")
    assert has_element?(view, "#to-buy " <> line("onion"))
  end

  test "copy as text holds the unticked lines and items", %{conn: conn, scope: scope} do
    {:ok, _} = Shopping.add_item(scope, %{text: "Milk"})
    {:ok, _} = Shopping.tick(scope, "salt")
    {:ok, view, _html} = live(conn, ~p"/shopping")

    text =
      view
      |> element("#copy-list")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-text")
      |> hd()

    assert text == "kidney beans: 400 g\nolive oil: 2 tbsp\nonion: 1\nMilk"
  end

  test "the nav links to shopping", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/plan")
    assert has_element?(view, "#nav-shopping[href='/shopping']")
  end

  describe "staples page" do
    test "adds and removes staples, which leave the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shopping/staples")
      assert has_element?(view, "#no-staples")

      view |> form("#staple-form", staple: %{name: ""}) |> render_change()
      assert has_element?(view, "#staple-form", "can't be blank")

      view |> form("#staple-form", staple: %{name: "Salt"}) |> render_submit()
      assert has_element?(view, "#staple-list", "Salt")

      view |> form("#staple-form", staple: %{name: "salt"}) |> render_submit()
      assert has_element?(view, "#staple-form", "is already a staple")

      {:ok, list, _html} = live(conn, ~p"/shopping")
      assert has_element?(list, "#staples", "salt")

      view |> element("#staple-list button[aria-label='Remove Salt']") |> render_click()
      assert has_element?(view, "#no-staples")
      assert has_element?(list, "#to-buy " <> line("salt"))
    end
  end
end
