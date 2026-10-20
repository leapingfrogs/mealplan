defmodule Mealplan.ArchivingTest do
  @moduledoc """
  The archive rule: deleting a recipe, meal or slot that a plan before today
  used archives it instead; anything else is deleted. History keeps what
  past planned meals were made of.
  """
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Households
  alias Mealplan.Households.MealSlot
  alias Mealplan.Meals
  alias Mealplan.Meals.Meal
  alias Mealplan.Meals.MealRecipe
  alias Mealplan.Planning
  alias Mealplan.Planning.Leftover
  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Planning.SlotSkip
  alias Mealplan.Recipes
  alias Mealplan.Recipes.Recipe

  setup do
    %{scope: scope} = household = household_fixture()
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})
    chilli = recipe_fixture(scope, %{name: "Chilli"})
    rice = recipe_fixture(scope, %{name: "Rice"})
    today = Planning.today(scope)

    Map.merge(household, %{
      slots: slots,
      chilli: chilli,
      rice: rice,
      meal: meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice]),
      today: today,
      past: Date.add(today, -3),
      future: Date.add(today, 2)
    })
  end

  defp plan(scope, date, slot, meal) do
    {:ok, planned_meal} = Planning.plan_meal(scope, date, slot.id, meal.id, 2)
    planned_meal
  end

  defp names(recipes), do: Enum.map(recipes, & &1.name)
  defp current(scope, meal), do: scope |> Meals.get_meal!(meal.id) |> Map.fetch!(:meal_recipes)

  describe "deleting a recipe" do
    test "never planned: taken out of its meals and deleted",
         %{scope: scope, chilli: chilli} = c do
      assert %{meals: [%Meal{name: "Chilli and rice"}], archive?: false} =
               Recipes.deletion_preview(scope, chilli)

      assert {:ok, :deleted} = Recipes.delete_recipe(scope, chilli)
      refute Repo.get(Recipe, chilli.id)
      assert scope |> current(c.meal) |> Enum.map(& &1.recipe.name) == ["Rice"]
    end

    test "used by a past plan: archived, while history keeps it",
         %{scope: scope, chilli: chilli, meal: meal, past: past, today: today} = c do
      plan(scope, past, c.slots["dinner"], meal)
      assert %{archive?: true} = Recipes.deletion_preview(scope, chilli)

      assert {:ok, :archived} = Recipes.delete_recipe(scope, chilli)

      assert Repo.get!(Recipe, chilli.id).archived_at
      refute "Chilli" in names(Recipes.list_recipes(scope))
      assert names(Recipes.list_archived_recipes(scope)) == ["Chilli"]

      # The meal no longer has it, but the past planned meal still does.
      assert scope |> current(meal) |> Enum.map(& &1.recipe.name) == ["Rice"]
      assert names(Meals.recipes_on(scope, meal.id, past)) == ["Chilli", "Rice"]
      assert names(Meals.recipes_on(scope, meal.id, today)) == ["Rice"]
    end

    test "leftover links for it from today on go; past ones stay",
         %{scope: scope, chilli: chilli, meal: meal, past: past, today: today} = c do
      old_source = plan(scope, Date.add(past, -1), c.slots["dinner"], meal)
      old_eater = plan(scope, past, c.slots["lunch"], meal)
      {:ok, _} = Planning.add_leftover(scope, old_eater.id, old_source.id, chilli.id)
      source = plan(scope, today, c.slots["breakfast"], meal)
      eater = plan(scope, c.future, c.slots["lunch"], meal)
      {:ok, _} = Planning.add_leftover(scope, eater.id, source.id, chilli.id)

      assert {:ok, :archived} = Recipes.delete_recipe(scope, chilli)

      assert [%Leftover{planned_meal_id: id}] = Repo.all(Leftover)
      assert id == old_eater.id
    end

    test "restoring brings it back to lists, not to meals", %{scope: scope, chilli: chilli} = c do
      plan(scope, c.past, c.slots["dinner"], c.meal)
      {:ok, :archived} = Recipes.delete_recipe(scope, chilli)

      assert {:ok, %Recipe{archived_at: nil}} = Recipes.restore_recipe(scope, chilli.id)
      assert "Chilli" in names(Recipes.list_recipes(scope))
      assert scope |> current(c.meal) |> Enum.map(& &1.recipe.name) == ["Rice"]

      assert Recipes.restore_recipe(scope, chilli.id) == {:error, :not_found}
      assert Recipes.restore_recipe(scope, "nope") == {:error, :not_found}
    end

    test "only the household's own", %{chilli: chilli} do
      %{scope: other_scope} = household_fixture()
      assert Recipes.delete_recipe(other_scope, chilli) == {:error, :not_found}
      assert Recipes.restore_recipe(other_scope, chilli.id) == {:error, :not_found}
    end
  end

  describe "taking a recipe out of a meal" do
    test "keeps the link for past plans, and it can come back",
         %{scope: scope, chilli: chilli, meal: meal, past: past, today: today} = c do
      plan(scope, past, c.slots["dinner"], meal)

      {:ok, _} = Meals.remove_recipe(scope, meal.id, chilli.id)

      assert [%MealRecipe{removed_on: ^today}] =
               Repo.all(from mr in MealRecipe, where: mr.recipe_id == ^chilli.id)

      assert names(Meals.recipes_on(scope, meal.id, past)) == ["Chilli", "Rice"]

      {:ok, _} = Meals.add_recipe(scope, meal.id, chilli.id)
      assert scope |> current(meal) |> Enum.map(& &1.recipe.name) == ["Rice", "Chilli"]
      assert names(Meals.recipes_on(scope, meal.id, today)) == ["Rice", "Chilli"]
      assert Meals.add_recipe(scope, meal.id, chilli.id) == {:error, :already_in_meal}
    end

    test "deletes the link when no past plan relied on it",
         %{scope: scope, chilli: chilli, meal: meal} = c do
      plan(scope, c.future, c.slots["dinner"], meal)
      {:ok, _} = Meals.remove_recipe(scope, meal.id, chilli.id)
      assert Repo.all(from mr in MealRecipe, where: mr.recipe_id == ^chilli.id) == []
    end

    test "a meal planned into the past today still has its recipes there",
         %{scope: scope, meal: meal, past: past} = c do
      # Filling in last week after the fact.
      plan(scope, past, c.slots["dinner"], meal)
      assert names(Meals.recipes_on(scope, meal.id, past)) == ["Chilli", "Rice"]
      assert %{archive?: true} = Recipes.deletion_preview(scope, c.chilli)

      %{scope: other_scope} = household_fixture()
      assert Meals.recipes_on(other_scope, meal.id, past) == []
    end
  end

  describe "deleting a meal" do
    test "never planned before today: its upcoming plans go and it is deleted",
         %{scope: scope, meal: meal, today: today} = c do
      planned = plan(scope, today, c.slots["dinner"], meal)
      :ok = Households.subscribe(scope)

      assert %{upcoming: [%PlannedMeal{id: id}], archive?: false} =
               Meals.deletion_preview(scope, meal)

      assert id == planned.id

      assert {:ok, :deleted} = Meals.delete_meal(scope, meal)
      refute Repo.get(Meal, meal.id)
      refute Repo.get(PlannedMeal, planned.id)
      week = Planning.week_start(today)
      assert_receive {:plan_changed, ^week}
    end

    test "planned before today: archived; past plans stay, upcoming ones go",
         %{scope: scope, meal: meal} = c do
      past = plan(scope, c.past, c.slots["dinner"], meal)
      upcoming = plan(scope, c.future, c.slots["dinner"], meal)

      assert {:ok, :archived} = Meals.delete_meal(scope, meal)

      assert Repo.get(PlannedMeal, past.id)
      refute Repo.get(PlannedMeal, upcoming.id)
      refute "Chilli and rice" in names(Meals.list_meals(scope))
      assert names(Meals.list_archived_meals(scope)) == ["Chilli and rice"]
      assert names(Meals.recipes_on(scope, meal.id, c.past)) == ["Chilli", "Rice"]
    end

    test "restoring, unless another meal took the name", %{scope: scope, meal: meal} = c do
      plan(scope, c.past, c.slots["dinner"], meal)
      {:ok, :archived} = Meals.delete_meal(scope, meal)
      {:ok, newer} = Meals.create_meal(scope, %{name: "CHILLI AND RICE"})

      assert {:error, %Ecto.Changeset{}} = Meals.restore_meal(scope, meal.id)

      {:ok, _} = Meals.rename_meal(scope, newer.id, %{name: "Something else"})
      assert {:ok, %Meal{archived_at: nil}} = Meals.restore_meal(scope, meal.id)
      assert Meals.restore_meal(scope, meal.id) == {:error, :not_found}
    end

    test "only the household's own", %{meal: meal} do
      %{scope: other_scope} = household_fixture()
      assert Meals.delete_meal(other_scope, meal) == {:error, :not_found}
      assert Meals.restore_meal(other_scope, meal.id) == {:error, :not_found}
    end
  end

  describe "deleting a slot" do
    test "upcoming meals must be moved or removed first",
         %{scope: scope, slots: slots, meal: meal} = c do
      upcoming = plan(scope, c.future, slots["snack"], meal)

      assert {:ok, %{upcoming: [%{id: id}], archive?: false}} =
               Households.slot_deletion_preview(scope, slots["snack"].id)

      assert id == upcoming.id
      assert Households.delete_meal_slot(scope, slots["snack"].id) == {:error, :has_upcoming}

      assert Households.delete_meal_slot(scope, slots["snack"].id, slots["snack"].id) ==
               {:error, :has_upcoming}

      assert {:ok, %MealSlot{archived_at: nil}} =
               Households.delete_meal_slot(scope, slots["snack"].id, slots["lunch"].id)

      assert %{date: date, meal_slot_id: slot_id} = Repo.reload!(upcoming)
      assert {date, slot_id} == {c.future, slots["lunch"].id}
      refute Repo.get(MealSlot, slots["snack"].id)
    end

    test "or removed", %{scope: scope, slots: slots, meal: meal} = c do
      upcoming = plan(scope, c.future, slots["snack"], meal)

      assert {:ok, _slot} = Households.delete_meal_slot(scope, slots["snack"].id, :remove)
      refute Repo.get(PlannedMeal, upcoming.id)
    end

    test "moving to a slot that doesn't exist changes nothing",
         %{scope: scope, slots: slots, meal: meal} = c do
      upcoming = plan(scope, c.future, slots["snack"], meal)

      assert {:error, :not_found} =
               Households.delete_meal_slot(scope, slots["snack"].id, Ecto.UUID.generate())

      assert Repo.reload!(upcoming).meal_slot_id == slots["snack"].id
      assert Repo.get(MealSlot, slots["snack"].id)
    end

    test "used by a past plan: archived, and past weeks still show it",
         %{scope: scope, slots: slots, meal: meal} = c do
      past = plan(scope, c.past, slots["snack"], meal)
      {:ok, _} = Planning.skip_slot(scope, c.future, slots["snack"].id)

      assert {:ok, %{archive?: true}} = Households.slot_deletion_preview(scope, slots["snack"].id)

      assert {:ok, %MealSlot{archived_at: %DateTime{}}} =
               Households.delete_meal_slot(scope, slots["snack"].id)

      refute "Snack" in Enum.map(Households.list_meal_slots(scope), & &1.name)
      assert Repo.all(SlotSkip) == []

      week = Planning.get_week(scope, c.past)
      assert [%MealSlot{name: "Snack"}] = week.retired_slots
      assert Enum.any?(week.planned_meals, &(&1.id == past.id))
      assert week.cells == 21

      # Restoring the defaults brings back a fresh Snack slot.
      assert {:ok, 1} = Households.restore_default_meal_slots(scope)
    end

    test "is owner only", %{slots: slots, household: household} do
      %{scope: member_scope} = member_fixture(household)

      assert Households.delete_meal_slot(member_scope, slots["snack"].id, :remove) ==
               {:error, :unauthorized}

      assert Households.slot_deletion_preview(member_scope, "nope") == {:error, :not_found}
    end
  end
end
