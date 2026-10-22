defmodule MealplanWeb.PlanLive.LeftoversTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Planning
  alias Mealplan.Repo

  setup :register_and_log_in_user_with_household

  setup %{scope: scope} do
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    chilli = recipe_fixture(scope, %{name: "Chilli", servings: 4})
    rice = recipe_fixture(scope, %{name: "Rice", servings: 4})
    salad = recipe_fixture(scope, %{name: "Salad", servings: 2})

    %{
      slots: slots,
      chilli: chilli,
      rice: rice,
      salad: salad,
      chilli_night: meal_fixture(scope, %{name: "Chilli night"}, [chilli]),
      chilli_rice: meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice]),
      chilli_salad: meal_fixture(scope, %{name: "Chilli and salad"}, [chilli, salad]),
      monday: Planning.current_week(scope)
    }
  end

  defp plan(scope, date, slot, meal, servings) do
    {:ok, planned_meal} = Planning.plan_meal(scope, date, slot.id, meal.id, servings)
    planned_meal
  end

  defp open_leftovers(view, date, slot, servings) do
    view |> element("#cell-#{date}-#{slot.id} button", "Add") |> render_click()
    view |> element("#sheet-tab-leftovers") |> render_click()

    # Step the servings down (or up) to what's wanted.
    current =
      view
      |> element("#add-servings output")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.trim()
      |> String.to_integer()

    for _ <- 1..abs(servings - current)//1 do
      delta = if servings < current, do: "-1", else: "1"
      view |> element("#add-servings button[phx-value-delta='#{delta}']") |> render_click()
    end
  end

  # The design's examples, for a chilli recipe that serves 4.
  test "planned for 4 with 2 leftover servings: Monday cooks 6",
       %{conn: conn, scope: scope, slots: slots, monday: monday} = c do
    source = plan(scope, monday, slots["dinner"], c.chilli_night, 4)
    wednesday = Date.add(monday, 2)
    {:ok, view, _html} = live(conn, "/plan/#{monday}")

    open_leftovers(view, wednesday, slots["lunch"], 2)
    assert has_element?(view, "#source-#{source.id}", "cooks 4")
    view |> element("#source-#{source.id}-#{c.chilli.id}") |> render_click()

    refute has_element?(view, "#plan-sheet")
    assert has_element?(view, "#planned-#{source.id} .cooks", "cooks 6")
    assert has_element?(view, "#cell-#{wednesday}-#{slots["lunch"].id} .leftovers")
  end

  test "planned for 2 with 2 leftover servings: Monday cooks 4",
       %{conn: conn, scope: scope, slots: slots, monday: monday} = c do
    source = plan(scope, monday, slots["dinner"], c.chilli_night, 2)
    {:ok, view, _html} = live(conn, "/plan/#{monday}")
    refute has_element?(view, "#planned-#{source.id} .cooks")

    open_leftovers(view, Date.add(monday, 2), slots["lunch"], 2)
    view |> element("#source-#{source.id}-#{c.chilli.id}") |> render_click()

    assert has_element?(view, "#planned-#{source.id} .cooks", "cooks 4")
  end

  test "one recipe as leftovers while the rest is fresh",
       %{conn: conn, scope: scope, slots: slots, monday: monday} = c do
    source = plan(scope, monday, slots["dinner"], c.chilli_rice, 4)
    eater = plan(scope, Date.add(monday, 2), slots["lunch"], c.chilli_salad, 2)
    {:ok, view, _html} = live(conn, "/plan/#{monday}")

    view |> element("#planned-#{eater.id} button") |> render_click()
    assert has_element?(view, "#sheet-recipe-#{c.salad.id}", "cooked fresh")
    refute has_element?(view, "#use-#{c.salad.id}-#{source.id}")

    view |> element("#use-#{c.chilli.id}-#{source.id}") |> render_click()

    assert has_element?(view, "#sheet-recipe-#{c.chilli.id}", "Leftovers from")
    assert has_element?(view, "#sheet-recipe-#{c.salad.id}", "cooked fresh")
    assert has_element?(view, "#planned-#{source.id} .cooks", "cooks 6")

    # And back again.
    view |> element("#sheet-recipe-#{c.chilli.id} button", "Make fresh") |> render_click()
    refute has_element?(view, "#planned-#{source.id} .cooks")
  end

  test "the whole meal as leftovers",
       %{conn: conn, scope: scope, slots: slots, monday: monday} = c do
    source = plan(scope, monday, slots["dinner"], c.chilli_rice, 4)
    {:ok, view, _html} = live(conn, "/plan/#{monday}")

    open_leftovers(view, Date.add(monday, 1), slots["lunch"], 2)
    view |> element("#source-#{source.id} button", "All of it") |> render_click()

    [eater] = Enum.reject(Planning.get_week(scope, monday).planned_meals, &(&1.id == source.id))
    assert eater.meal_id == c.chilli_rice.id
    assert length(eater.leftovers) == 2

    view |> element("#planned-#{source.id} button") |> render_click()
    assert has_element?(view, "#sheet-recipe-#{c.rice.id}", "cooks 6 · leftovers for")
  end

  test "a weekend batch feeds the following week",
       %{conn: conn, scope: scope, slots: slots, monday: monday} = c do
    sunday = Date.add(monday, -1)
    source = plan(scope, sunday, slots["dinner"], c.chilli_night, 2)
    {:ok, view, _html} = live(conn, "/plan/#{monday}")

    open_leftovers(view, Date.add(monday, 1), slots["dinner"], 2)
    assert has_element?(view, "#source-#{source.id}", Calendar.strftime(sunday, "%a %-d %b"))
    view |> element("#source-#{source.id}-#{c.chilli.id}") |> render_click()

    {:ok, last_week, _html} = live(conn, "/plan/#{Planning.week_start(sunday)}")
    assert has_element?(last_week, "#planned-#{source.id} .cooks", "cooks 4")
  end

  test "with nothing earlier, the tab says so", %{conn: conn, slots: slots, monday: monday} do
    {:ok, view, _html} = live(conn, "/plan/#{monday}")
    open_leftovers(view, monday, slots["breakfast"], 1)
    assert has_element?(view, "#leftover-sources", "Nothing cooked")

    view |> element("#sheet-tab-new") |> render_click()
    assert has_element?(view, "#sheet-search")
  end

  describe "moving or removing linked meals" do
    setup %{scope: scope, slots: slots, monday: monday} = c do
      source = plan(scope, monday, slots["dinner"], c.chilli_night, 4)
      eater = plan(scope, Date.add(monday, 2), slots["lunch"], c.chilli_night, 2)
      {:ok, _} = Planning.add_leftover(scope, eater.id, source.id, c.chilli.id)
      %{source: source, eater: eater}
    end

    test "moving asks first, then says which links no longer apply",
         %{conn: conn, slots: slots, monday: monday, source: source} do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      view |> element("#planned-#{source.id} button") |> render_click()
      friday = Date.add(monday, 4)
      move = %{date: Date.to_iso8601(friday), slot: slots["dinner"].id}

      view |> form("#move-form", move: move) |> render_submit()
      assert has_element?(view, "#confirm-move", "Its leftovers feed")
      assert Repo.reload!(source).date == monday

      view |> element("#confirm-move button", "Cancel") |> render_click()
      refute has_element?(view, "#confirm-move")

      view |> form("#move-form", move: move) |> render_submit()
      html = view |> element("#confirm-move button", "Move anyway") |> render_click()

      assert html =~ "One leftover link no longer applied."
      assert Repo.reload!(source).date == friday
      refute has_element?(view, "#planned-#{source.id} .cooks")
    end

    test "a move that keeps the link says nothing about it",
         %{conn: conn, slots: slots, monday: monday, source: source} do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      view |> element("#planned-#{source.id} button") |> render_click()

      view
      |> form("#move-form",
        move: %{date: Date.to_iso8601(Date.add(monday, 1)), slot: slots["dinner"].id}
      )
      |> render_submit()

      html = view |> element("#confirm-move button", "Move anyway") |> render_click()
      assert html =~ "Moved to"
      refute html =~ "no longer applied"
      assert has_element?(view, "#planned-#{source.id} .cooks", "cooks 6")
    end

    test "removing warns which meal will be cooked fresh",
         %{conn: conn, monday: monday, source: source, eater: eater} do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      view |> element("#planned-#{source.id} button") |> render_click()

      confirm =
        view
        |> element("#remove-planned-meal")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-confirm")
        |> hd()

      assert confirm =~
               "#{Calendar.strftime(eater.date, "%a %-d %b")} lunch will then be cooked fresh"

      view |> element("#remove-planned-meal") |> render_click()
      refute has_element?(view, "#planned-#{eater.id} .leftovers")
    end

    test "the eater's sheet warns too", %{conn: conn, monday: monday, eater: eater} do
      {:ok, view, _html} = live(conn, "/plan/#{monday}")
      view |> element("#planned-#{eater.id} button") |> render_click()

      view |> form("#move-form", move: %{date: Date.to_iso8601(monday)}) |> render_submit()
      assert has_element?(view, "#confirm-move", "It eats leftovers from")
    end
  end
end
