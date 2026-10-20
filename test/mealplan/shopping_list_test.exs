defmodule Mealplan.ShoppingListTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Households
  alias Mealplan.Planning
  alias Mealplan.Shopping
  alias Mealplan.Shopping.Item
  alias Mealplan.Shopping.ShoppingList
  alias Mealplan.Shopping.View

  setup do
    %{scope: scope} = household = household_fixture()
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

    Map.merge(household, %{slots: slots, today: today, meal: meal, planned: planned})
  end

  defp to_buy(scope), do: for(%{line: l} <- Shopping.view(scope).to_buy, do: l.key)
  defp ticked(scope), do: for(%{line: l} <- Shopping.view(scope).ticked, do: l.key)

  defp more(scope, key) do
    entry = Enum.find(Shopping.view(scope).to_buy, &(&1.line.key == key))
    entry.more && Mealplan.Shopping.Quantity.to_string(entry.more)
  end

  describe "the list and its range" do
    test "is created once, for today to the end of the planning week", %{scope: scope} = c do
      list = Shopping.get_list(scope)
      assert list.starts_on == c.today
      assert list.ends_on == Date.add(Planning.default_week(scope), 6)
      assert Shopping.get_list(scope).id == list.id
      assert Repo.aggregate(ShoppingList, :count) == 1
    end

    test "the range can change, up to 14 days, and keeps ticks", %{scope: scope, today: today} do
      :ok = Households.subscribe(scope)
      {:ok, _} = Shopping.tick(scope, "onion")

      assert {:ok, %{ends_on: ends_on}} =
               Shopping.set_range(scope, %{starts_on: today, ends_on: Date.add(today, 13)})

      assert ends_on == Date.add(today, 13)
      assert_receive {:shopping_changed, _id}
      assert ticked(scope) == ["onion"]

      assert {:error, changeset} =
               Shopping.set_range(scope, %{starts_on: today, ends_on: Date.add(today, 14)})

      assert "is more than 14 days on" in errors_on(changeset).ends_on

      assert {:error, changeset} =
               Shopping.set_range(scope, %{starts_on: today, ends_on: Date.add(today, -1)})

      assert "is before the start" in errors_on(changeset).ends_on
      assert {:error, _changeset} = Shopping.set_range(scope, %{starts_on: nil})
    end

    test "a household only ever sees its own list", %{scope: scope} do
      {:ok, _} = Shopping.tick(scope, "onion")
      %{scope: other} = household_fixture()

      assert Shopping.view(other).to_buy == []
      assert Shopping.get_list(other).id != Shopping.get_list(scope).id
      assert Shopping.tick(other, "onion") == {:error, :not_found}
    end
  end

  describe "ticking" do
    test "ticked lines move to ticked; unticking brings them back", %{scope: scope} do
      assert to_buy(scope) == ["kidney bean", "olive oil", "onion", "salt"]

      :ok = Households.subscribe(scope)
      {:ok, _} = Shopping.tick(scope, "onion")
      assert_receive {:shopping_changed, _id}
      assert ticked(scope) == ["onion"]
      refute "onion" in to_buy(scope)

      {:ok, _} = Shopping.untick(scope, "onion")
      assert ticked(scope) == []
      assert Shopping.tick(scope, "caviar") == {:error, :not_found}
    end

    test "when more is needed the line comes back showing how much; less stays ticked",
         %{scope: scope} = c do
      {:ok, _} = Shopping.tick(scope, "kidney bean")
      {:ok, _} = Shopping.tick(scope, "onion")
      {:ok, _} = Shopping.tick(scope, "olive oil")

      {:ok, _} = Planning.set_servings(scope, c.planned.id, 6)
      assert more(scope, "kidney bean") == "200 g"
      assert more(scope, "olive oil") == "1 tbsp"
      # 1.5 onions round up to 2: one more.
      assert more(scope, "onion") == "1"

      {:ok, _} = Shopping.tick(scope, "onion")
      {:ok, _} = Planning.set_servings(scope, c.planned.id, 5)
      assert "onion" in ticked(scope)
      assert more(scope, "kidney bean") == "100 g"
    end

    test "a line no longer needed keeps its tick, hidden, until a new list",
         %{scope: scope} = c do
      {:ok, _} = Shopping.tick(scope, "onion")
      today = c.today

      # The range moves past the meal, then back.
      {:ok, _} =
        Shopping.set_range(scope, %{starts_on: Date.add(today, 1), ends_on: Date.add(today, 2)})

      assert Shopping.view(scope).ticked == []
      {:ok, _} = Shopping.set_range(scope, %{starts_on: today, ends_on: Date.add(today, 2)})
      assert ticked(scope) == ["onion"]

      # The plan drops the meal, then plans it again.
      {:ok, _} = Planning.remove_planned_meal(scope, c.planned.id)
      assert Shopping.view(scope).ticked == []
      {:ok, _} = Planning.plan_meal(scope, today, c.slots["lunch"].id, c.meal.id, 4)
      assert ticked(scope) == ["onion"]

      {:ok, _} = Shopping.start_new(scope)
      assert "onion" in to_buy(scope)
    end
  end

  describe "staples" do
    test "are left off the list but listed apart, matched by key", %{scope: scope} do
      :ok = Households.subscribe(scope)
      assert {:ok, salt} = Shopping.add_staple(scope, %{name: " Salt "})
      assert_receive {:shopping_changed, _id}
      {:ok, _} = Shopping.add_staple(scope, %{name: "Kidney  Beans"})

      view = Shopping.view(scope)
      assert Enum.map(view.staples, & &1.key) == ["kidney bean", "salt"]
      assert to_buy(scope) == ["olive oil", "onion"]
      assert Enum.map(Shopping.list_staples(scope), & &1.name) == ["Kidney Beans", "Salt"]

      assert {:error, changeset} = Shopping.add_staple(scope, %{name: "salt"})
      assert "is already a staple" in errors_on(changeset).name
      assert {:error, _changeset} = Shopping.add_staple(scope, %{name: ""})

      assert {:ok, _} = Shopping.remove_staple(scope, salt.id)
      assert "salt" in to_buy(scope)
    end

    test "belong to the household", %{scope: scope} do
      {:ok, salt} = Shopping.add_staple(scope, %{name: "Salt"})
      %{scope: other} = household_fixture()

      assert Shopping.remove_staple(other, salt.id) == {:error, :not_found}
      assert Shopping.remove_staple(other, "nope") == {:error, :not_found}
      assert Shopping.list_staples(other) == []
      assert {:ok, _} = Shopping.add_staple(other, %{name: "Salt"})
    end
  end

  describe "manual items" do
    test "are added in order, ticked, untick and removed", %{scope: scope} do
      :ok = Households.subscribe(scope)
      {:ok, roll} = Shopping.add_item(scope, %{text: "  Kitchen   roll "})
      assert_receive {:shopping_changed, _id}
      {:ok, milk} = Shopping.add_item(scope, %{text: "Milk 2 l"})

      assert Enum.map(Shopping.view(scope).items, & &1.text) == ["Kitchen roll", "Milk 2 l"]
      assert {:error, _changeset} = Shopping.add_item(scope, %{text: " "})

      assert {:ok, %Item{ticked_at: %DateTime{}}} = Shopping.tick_item(scope, roll.id, true)
      assert {:ok, %Item{ticked_at: nil}} = Shopping.tick_item(scope, roll.id, false)
      assert {:ok, _} = Shopping.remove_item(scope, milk.id)
      assert Enum.map(Shopping.view(scope).items, & &1.text) == ["Kitchen roll"]
    end

    test "belong to the household", %{scope: scope} do
      {:ok, roll} = Shopping.add_item(scope, %{text: "Kitchen roll"})
      %{scope: other} = household_fixture()

      assert Shopping.tick_item(other, roll.id, true) == {:error, :not_found}
      assert Shopping.remove_item(other, roll.id) == {:error, :not_found}
      assert Shopping.remove_item(scope, "nope") == {:error, :not_found}
    end
  end

  test "starting a new list clears ticks and bought items, keeps the rest, resets the range",
       %{scope: scope, today: today} do
    {:ok, _} = Shopping.set_range(scope, %{starts_on: Date.add(today, -3), ends_on: today})
    {:ok, _} = Shopping.tick(scope, "onion")
    {:ok, roll} = Shopping.add_item(scope, %{text: "Kitchen roll"})
    {:ok, _milk} = Shopping.add_item(scope, %{text: "Milk"})
    {:ok, _} = Shopping.tick_item(scope, roll.id, true)

    :ok = Households.subscribe(scope)
    assert {:ok, %ShoppingList{}} = Shopping.start_new(scope)
    assert_receive {:shopping_changed, _id}

    assert %View{ticked: [], items: [%{text: "Milk"}], list: list} = Shopping.view(scope)
    assert {list.starts_on, list.ends_on} == Shopping.default_range(scope)
  end
end
