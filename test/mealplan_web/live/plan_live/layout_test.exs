defmodule MealplanWeb.PlanLive.LayoutTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.MealsFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households
  alias Mealplan.Planning

  setup :register_and_log_in_user_with_household

  setup %{scope: scope} do
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    %{slots: slots, today: Planning.today(scope), meal: meal_fixture(scope, %{name: "Porridge"})}
  end

  test "phones get a strip of the week's days, marking today", %{conn: conn, today: today} do
    {:ok, view, _html} = live(conn, "/plan/#{Planning.week_start(today)}")

    for day <- Date.range(Planning.week_start(today), Date.add(Planning.week_start(today), 6)) do
      assert has_element?(view, "#day-strip a[href='#day-#{day}']")
    end

    assert has_element?(view, "#day-strip a[aria-current=date][href='#day-#{today}']")
    assert has_element?(view, "#day-#{today}[data-today=true]")
  end

  test "slots line up as rows on desktop: one per slot plus the day header", %{
    conn: conn,
    today: today
  } do
    {:ok, view, _html} = live(conn, "/plan/#{Planning.week_start(today)}")
    assert has_element?(view, "#days[data-rows='5']")
  end

  test "every open slot has a labelled Add, and Skip while empty",
       %{conn: conn, scope: scope, slots: slots, today: today, meal: meal} do
    {:ok, _} = Planning.plan_meal(scope, today, slots["dinner"].id, meal.id)
    {:ok, view, _html} = live(conn, "/plan/#{Planning.week_start(today)}")
    weekday = Calendar.strftime(today, "%A")

    lunch = "#cell-#{today}-#{slots["lunch"].id}"
    dinner = "#cell-#{today}-#{slots["dinner"].id}"

    assert has_element?(view, "#{lunch} button[aria-label='Add to Lunch on #{weekday}']")
    assert has_element?(view, "#{lunch} button", "Skip")
    assert has_element?(view, "#{dinner} button[aria-label='Add to Dinner on #{weekday}']")
    refute has_element?(view, "#{dinner} button", "Skip")
  end

  test "past days this week fold to a summary until opened",
       %{conn: conn, scope: scope, slots: slots, today: today, meal: meal} do
    if Date.day_of_week(today) == 1 do
      # A Monday has no earlier days this week; nothing folds.
      {:ok, view, _html} = live(conn, "/plan/#{Planning.week_start(today)}")
      refute has_element?(view, "[id^=summary-]")
    else
      yesterday = Date.add(today, -1)
      {:ok, _} = Planning.plan_meal(scope, yesterday, slots["dinner"].id, meal.id)
      {:ok, _} = Planning.skip_slot(scope, yesterday, slots["breakfast"].id)
      {:ok, view, _html} = live(conn, "/plan/#{Planning.week_start(today)}")

      assert has_element?(view, "#summary-#{yesterday}", "1 meal planned · 1 skipped")
      assert has_element?(view, "#slots-#{yesterday}.hidden")
      refute has_element?(view, "#slots-#{today}.hidden")
      refute has_element?(view, "#toggle-day-#{today}")

      view |> element("#toggle-day-#{yesterday}") |> render_click()
      refute has_element?(view, "#slots-#{yesterday}.hidden")
      assert has_element?(view, "#toggle-day-#{yesterday}[aria-expanded=true]")

      view |> element("#toggle-day-#{yesterday}") |> render_click()
      assert has_element?(view, "#slots-#{yesterday}.hidden")
    end
  end

  test "other weeks don't fold", %{conn: conn, today: today} do
    {:ok, view, _html} = live(conn, "/plan/#{Date.add(Planning.week_start(today), -7)}")
    refute has_element?(view, "[id^=summary-]")
  end
end
