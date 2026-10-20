defmodule MealplanWeb.HouseholdLive.MealSlotsTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Households

  setup :register_and_log_in_user_with_household

  defp slot(scope, name), do: Enum.find(Households.list_meal_slots(scope), &(&1.name == name))
  defp names(scope), do: scope |> Households.list_meal_slots() |> Enum.map(& &1.name)

  defp row_order(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#meal-slots li[data-id]")
    |> Enum.map(&(&1 |> LazyHTML.attribute("data-id") |> hd()))
  end

  describe "the owner" do
    test "adds a slot", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/household")

      view |> form("#new-slot-form", new_slot: %{name: "Elevenses"}) |> render_submit()

      assert names(scope) == ~w(Breakfast Lunch Dinner Snack Elevenses)
      assert has_element?(view, "#slot-#{slot(scope, "Elevenses").id}", "Elevenses")
    end

    test "sees blank and duplicate names rejected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/household")

      html = view |> form("#new-slot-form", new_slot: %{name: " "}) |> render_change()
      assert html =~ "can&#39;t be blank"

      html = view |> form("#new-slot-form", new_slot: %{name: "dinner"}) |> render_submit()
      assert html =~ "is already a meal slot"
    end

    test "renames a slot", %{conn: conn, scope: scope} do
      lunch = slot(scope, "Lunch")
      {:ok, view, _html} = live(conn, ~p"/household")

      view |> element("#slot-#{lunch.id} button", "Rename") |> render_click()
      assert has_element?(view, "#rename-slot-form")

      view |> form("#rename-slot-form", slot: %{name: "Midday"}) |> render_submit()

      refute has_element?(view, "#rename-slot-form")
      assert has_element?(view, "#slot-#{lunch.id}", "Midday")
      assert names(scope) == ~w(Breakfast Midday Dinner Snack)
    end

    test "cancels a rename", %{conn: conn, scope: scope} do
      lunch = slot(scope, "Lunch")
      {:ok, view, _html} = live(conn, ~p"/household")

      view |> element("#slot-#{lunch.id} button", "Rename") |> render_click()
      view |> element("#rename-slot-form button", "Cancel") |> render_click()

      refute has_element?(view, "#rename-slot-form")
      assert has_element?(view, "#slot-#{lunch.id}", "Lunch")
    end

    test "moves slots with the arrow buttons", %{conn: conn, scope: scope} do
      snack = slot(scope, "Snack")
      {:ok, view, _html} = live(conn, ~p"/household")

      view |> element("#slot-#{snack.id} button[phx-value-direction=up]") |> render_click()

      assert names(scope) == ~w(Breakfast Lunch Snack Dinner)
      assert row_order(view) == Enum.map(Households.list_meal_slots(scope), & &1.id)
    end

    test "reorders by drag and drop", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/household")
      reversed = scope |> Households.list_meal_slots() |> Enum.map(& &1.id) |> Enum.reverse()

      view |> element("#meal-slots") |> render_hook("reorder_slots", %{ids: reversed})

      assert names(scope) == ~w(Snack Dinner Lunch Breakfast)
      assert row_order(view) == reversed
    end

    test "deletes a slot", %{conn: conn, scope: scope} do
      snack = slot(scope, "Snack")
      {:ok, view, _html} = live(conn, ~p"/household")

      view |> element("#slot-#{snack.id} button", "Delete") |> render_click()

      refute has_element?(view, "#slot-#{snack.id}")
      assert names(scope) == ~w(Breakfast Lunch Dinner)
    end

    test "is told a slot with planned meals can't be deleted yet", %{conn: conn, scope: scope} do
      snack = slot(scope, "Snack")
      meal = Mealplan.MealsFixtures.meal_fixture(scope)
      {:ok, _} = Mealplan.Planning.plan_meal(scope, ~D[2026-11-02], snack.id, meal.id)
      {:ok, view, _html} = live(conn, ~p"/household")

      html = view |> element("#slot-#{snack.id} button", "Delete") |> render_click()

      assert html =~ "has planned meals"
      assert has_element?(view, "#slot-#{snack.id}")
    end

    test "restores the defaults, offered only when one is missing", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/household")
      refute has_element?(view, "#restore-default-slots")

      {:ok, _} = Households.delete_meal_slot(scope, slot(scope, "Breakfast").id)
      assert has_element?(view, "#restore-default-slots")

      view |> element("#restore-default-slots") |> render_click()

      assert names(scope) == ~w(Breakfast Lunch Dinner Snack)
      refute has_element?(view, "#restore-default-slots")
    end

    test "sees a stale reorder refused and the current order", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/household")

      html =
        view
        |> element("#meal-slots")
        |> render_hook("reorder_slots", %{ids: [Ecto.UUID.generate()]})

      assert html =~ "Couldn&#39;t change the meal slots"
      assert names(scope) == ~w(Breakfast Lunch Dinner Snack)
    end
  end

  describe "a member" do
    setup %{household: household} do
      %{user: member} = member_fixture(household)
      %{member_conn: log_in_user(Phoenix.ConnTest.build_conn(), member)}
    end

    test "sees the slots read-only and their changes live",
         %{member_conn: member_conn, scope: owner_scope} do
      {:ok, view, _html} = live(member_conn, ~p"/household")

      assert has_element?(view, "#meal-slots", "Breakfast")
      refute has_element?(view, "#new-slot-form")
      refute has_element?(view, "#meal-slots button")
      refute has_element?(view, "#meal-slots li[draggable]")

      {:ok, _} = Households.create_meal_slot(owner_scope, %{name: "Elevenses"})
      assert has_element?(view, "#meal-slots", "Elevenses")
    end

    test "can't change slots by sending events", %{member_conn: member_conn, scope: owner_scope} do
      {:ok, view, _html} = live(member_conn, ~p"/household")
      lunch = slot(owner_scope, "Lunch")

      render_hook(view, "create_slot", %{new_slot: %{name: "Sneaky"}})
      render_hook(view, "delete_slot", %{id: lunch.id})
      render_hook(view, "move_slot", %{id: lunch.id, direction: "up"})

      assert names(owner_scope) == ~w(Breakfast Lunch Dinner Snack)
    end
  end

  test "the week page follows slot changes", %{conn: conn, scope: scope} do
    {:ok, week, _html} = live(conn, ~p"/plan")

    {:ok, _} = Households.rename_meal_slot(scope, slot(scope, "Lunch").id, %{name: "Midday"})

    assert has_element?(week, "#meal-slots", "Midday")
    refute has_element?(week, "#meal-slots", "Lunch")
  end
end
