defmodule Mealplan.MealSlotTagsTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Meals.MealSlotTag
  alias Mealplan.Planning

  setup do
    %{scope: scope} = household = household_fixture()
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    Map.merge(household, %{slots: slots, meal: meal_fixture(scope, %{name: "Chilli night"})})
  end

  defp slot_names(scope, meal),
    do: scope |> Meals.get_meal!(meal.id) |> Map.fetch!(:slots) |> Enum.map(& &1.name)

  test "set_slots/3 tags a meal, in day order, and tells the household", %{
    scope: scope,
    slots: slots,
    meal: meal
  } do
    :ok = Households.subscribe(scope)

    assert {:ok, _meal} = Meals.set_slots(scope, meal.id, [slots["dinner"].id, slots["lunch"].id])
    assert slot_names(scope, meal) == ["Lunch", "Dinner"]
    assert_receive {:meal_changed, id} when id == meal.id

    assert {:ok, _meal} =
             Meals.set_slots(scope, meal.id, [slots["breakfast"].id, slots["dinner"].id])

    assert slot_names(scope, meal) == ["Breakfast", "Dinner"]

    assert {:ok, _meal} = Meals.set_slots(scope, meal.id, [])
    assert slot_names(scope, meal) == []
  end

  test "meal lists load the tags", %{scope: scope, slots: slots, meal: meal} do
    {:ok, _} = Meals.set_slots(scope, meal.id, [slots["dinner"].id])
    assert [%{slots: [%{name: "Dinner"}]}] = Meals.list_meals(scope)
  end

  test "only the household's active slots, and its own meals", %{
    scope: scope,
    slots: slots,
    meal: meal
  } do
    %{scope: other_scope} = household_fixture()
    [their_slot | _] = Households.list_meal_slots(other_scope)
    their_meal = meal_fixture(other_scope)

    assert Meals.set_slots(scope, meal.id, [their_slot.id]) == {:error, :not_found}
    assert Meals.set_slots(scope, meal.id, ["nope"]) == {:error, :not_found}
    assert Meals.set_slots(scope, their_meal.id, [slots["lunch"].id]) == {:error, :not_found}
    assert Repo.aggregate(MealSlotTag, :count) == 0
  end

  test "an archived slot keeps its tags, hidden, and setting slots leaves them",
       %{scope: scope, slots: slots, meal: meal} do
    {:ok, _} = Meals.set_slots(scope, meal.id, [slots["snack"].id, slots["lunch"].id])

    {:ok, _} =
      Planning.plan_meal(scope, Date.add(Planning.today(scope), -2), slots["snack"].id, meal.id)

    {:ok, %{archived_at: %DateTime{}}} = Households.delete_meal_slot(scope, slots["snack"].id)

    assert slot_names(scope, meal) == ["Lunch"]
    {:ok, _} = Meals.set_slots(scope, meal.id, [])
    assert [%MealSlotTag{meal_slot_id: id}] = Repo.all(MealSlotTag)
    assert id == slots["snack"].id
  end

  test "planning with tag: true adds the slot once, and plans untagged in an archived slot",
       %{scope: scope, slots: slots, meal: meal} do
    today = Planning.today(scope)
    dinner = slots["dinner"].id
    {:ok, _} = Planning.plan_meal(scope, today, dinner, meal.id, nil, tag: true)
    {:ok, _} = Planning.plan_meal(scope, today, dinner, meal.id, nil, tag: true)
    assert slot_names(scope, meal) == ["Dinner"]

    {:ok, past} = Planning.plan_meal(scope, Date.add(today, -2), slots["snack"].id, meal.id)
    {:ok, %{archived_at: %DateTime{}}} = Households.delete_meal_slot(scope, slots["snack"].id)
    other = meal_fixture(scope, %{name: "Toast"})

    assert {:ok, _} = Planning.change_meal(scope, past.id, other.id, tag: true)
    assert slot_names(scope, other) == []
  end

  test "renaming a slot keeps its tags, and exports use the new name",
       %{scope: scope, slots: slots, meal: meal} do
    {:ok, _} = Meals.set_slots(scope, meal.id, [slots["dinner"].id])
    {:ok, _} = Households.rename_meal_slot(scope, slots["dinner"].id, %{name: "Tea"})

    assert slot_names(scope, meal) == ["Tea"]
    {:ok, {_name, zip}} = Mealplan.Transfer.export(scope)
    {:ok, files} = :zip.unzip(zip, [:memory])
    {_path, menu} = List.keyfind(files, ~c"meals.menu", 0)
    assert menu =~ "= Chilli night\n\n> Slots: Tea"
  end

  test "deleting a slot or a meal outright removes its tags", %{
    scope: scope,
    slots: slots,
    meal: meal
  } do
    {:ok, _} = Meals.set_slots(scope, meal.id, [slots["snack"].id, slots["lunch"].id])

    {:ok, %{archived_at: nil}} = Households.delete_meal_slot(scope, slots["snack"].id)
    assert Repo.aggregate(MealSlotTag, :count) == 1

    {:ok, :deleted} = Meals.delete_meal(scope, meal)
    assert Repo.aggregate(MealSlotTag, :count) == 0
  end

  test "an archived meal can't be tagged", %{scope: scope, slots: slots, meal: meal} do
    {:ok, _} =
      Planning.plan_meal(scope, Date.add(Planning.today(scope), -2), slots["lunch"].id, meal.id)

    {:ok, :archived} = Meals.delete_meal(scope, meal)
    assert Meals.set_slots(scope, meal.id, [slots["lunch"].id]) == {:error, :not_found}
  end

  test "the database refuses a tag across households", %{scope: scope, meal: meal} do
    %{scope: other_scope} = household_fixture()
    [their_slot | _] = Households.list_meal_slots(other_scope)

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%MealSlotTag{
        household_id: scope.household.id,
        meal_id: meal.id,
        meal_slot_id: their_slot.id
      })
    end
  end
end
