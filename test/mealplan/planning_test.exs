defmodule Mealplan.PlanningTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Planning.Leftover
  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Planning.SlotSkip
  alias Mealplan.Planning.Week

  # A Monday.
  @mon ~D[2026-11-02]
  @tue ~D[2026-11-03]
  @wed ~D[2026-11-04]

  setup do
    %{scope: scope} =
      household =
      household_fixture(Mealplan.AccountsFixtures.user_fixture(), %{usually_feeding: 3})

    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})

    chilli = recipe_fixture(scope, %{name: "Chilli", servings: 4})
    rice = recipe_fixture(scope, %{name: "Rice", servings: 2})
    salad = recipe_fixture(scope, %{name: "Salad", servings: 1})

    Map.merge(household, %{
      slots: slots,
      chilli: chilli,
      rice: rice,
      salad: salad,
      chilli_meal: meal_fixture(scope, %{name: "Chilli night"}, [chilli]),
      chilli_rice: meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice]),
      chilli_salad: meal_fixture(scope, %{name: "Chilli and salad"}, [chilli, salad])
    })
  end

  defp plan(scope, date, slot, meal, servings \\ nil) do
    {:ok, planned_meal} = Planning.plan_meal(scope, date, slot.id, meal.id, servings)
    planned_meal
  end

  defp cooking(scope, date) do
    scope
    |> Planning.get_week(date)
    |> Planning.cooking()
    |> Enum.map(
      &{&1.planned_meal.id, &1.recipe.name, &1.cooked_servings,
       Decimal.to_string(&1.scale, :normal)}
    )
  end

  describe "dates in the household's time zone" do
    defp in_zone(scope, time_zone),
      do: %{scope | household: %{scope.household | time_zone: time_zone}}

    test "today and the current week follow the household's clock", %{scope: scope} do
      london = in_zone(scope, "Europe/London")

      # Clocks went forward at 01:00 UTC on 29 March 2026: 23:30 UTC on Sunday
      # is already 00:30 on Monday in London.
      assert Planning.today(london, ~U[2026-03-29 23:30:00Z]) == ~D[2026-03-30]
      assert Planning.current_week(london, ~U[2026-03-29 23:30:00Z]) == ~D[2026-03-30]

      # They went back on 25 October: 23:30 UTC that Sunday is 23:30 in London.
      assert Planning.current_week(london, ~U[2026-10-25 23:30:00Z]) == ~D[2026-10-19]

      # New Zealand daylight time (UTC+13): Monday starts at 11:00 UTC on Sunday.
      auckland = in_zone(scope, "Pacific/Auckland")
      assert Planning.current_week(auckland, ~U[2026-10-25 10:59:00Z]) == ~D[2026-10-19]
      assert Planning.current_week(auckland, ~U[2026-10-25 11:00:00Z]) == ~D[2026-10-26]

      # US clocks went back on 1 November: 06:30 UTC on Monday is still
      # Sunday evening in Los Angeles.
      los_angeles = in_zone(scope, "America/Los_Angeles")
      assert Planning.today(los_angeles, ~U[2026-11-02 06:30:00Z]) == ~D[2026-11-01]
      assert Planning.current_week(los_angeles, ~U[2026-11-02 06:30:00Z]) == ~D[2026-10-26]
      assert Planning.current_week(los_angeles, ~U[2026-11-02 08:00:00Z]) == ~D[2026-11-02]
    end

    test "use the real clock by default", %{scope: scope} do
      today = Planning.today(scope)
      assert Planning.current_week(scope) == Planning.week_start(today)
      assert Planning.default_week(scope) == Planning.current_week(scope)
    end

    test "weeks start on Monday" do
      assert Planning.week_start(~D[2026-11-08]) == @mon
      assert Planning.week_start(@mon) == @mon
      assert Planning.week_start(@wed) == @mon
    end
  end

  describe "the week and its status" do
    test "counts cells with a meal or a skip among active slots",
         %{scope: scope, slots: slots} = c do
      plan(scope, @mon, slots["dinner"], c.chilli_meal)
      plan(scope, @mon, slots["dinner"], c.chilli_rice)
      plan(scope, @tue, slots["lunch"], c.chilli_meal)
      {:ok, _} = Planning.skip_slot(scope, @wed, slots["breakfast"].id)
      # Outside the week.
      plan(scope, Date.add(@mon, 7), slots["lunch"], c.chilli_meal)

      week = Planning.get_week(scope, @wed)

      assert week.start == @mon
      assert week.days == Enum.to_list(Date.range(@mon, Date.add(@mon, 6)))
      assert length(week.planned_meals) == 3
      assert {week.planned, week.cells} == {3, 28}
      refute Week.fully_planned?(week)
    end

    test "the planner opens on next week once this one is fully planned",
         %{scope: scope, slots: slots} = c do
      now = ~U[2026-11-04 12:00:00Z]
      assert Planning.default_week(scope, now) == @mon

      for day <- Date.range(@mon, Date.add(@mon, 6)), {key, slot} <- slots do
        if key == "dinner",
          do: plan(scope, day, slot, c.chilli_meal),
          else: {:ok, _} = Planning.skip_slot(scope, day, slot.id)
      end

      assert Week.fully_planned?(Planning.get_week(scope, @mon))
      assert Planning.default_week(scope, now) == Date.add(@mon, 7)
    end

    test "a week with no slots is never fully planned" do
      refute Week.fully_planned?(%Week{planned: 0, cells: 0})
    end
  end

  describe "planning meals" do
    test "defaults to the household's usual servings and orders meals in a slot",
         %{scope: scope, slots: slots} = c do
      :ok = Households.subscribe(scope)

      first = plan(scope, @mon, slots["dinner"], c.chilli_meal)
      second = plan(scope, @mon, slots["dinner"], c.chilli_rice, 6)

      assert {first.servings, first.position} == {3, 0}
      assert {second.servings, second.position} == {6, 1}
      assert_receive {:plan_changed, @mon}
    end

    test "planning in a skipped slot removes the skip", %{scope: scope, slots: slots} = c do
      {:ok, _} = Planning.skip_slot(scope, @mon, slots["lunch"].id)
      plan(scope, @mon, slots["lunch"], c.chilli_meal)

      assert Repo.aggregate(SlotSkip, :count) == 0
    end

    test "only the household's active slots and meals", %{scope: scope, slots: slots} = c do
      %{scope: other_scope} = household_fixture()
      [their_slot | _] = Households.list_meal_slots(other_scope)
      their_meal = meal_fixture(other_scope)

      assert Planning.plan_meal(scope, @mon, their_slot.id, c.chilli_meal.id) ==
               {:error, :not_found}

      assert Planning.plan_meal(scope, @mon, slots["lunch"].id, their_meal.id) ==
               {:error, :not_found}

      assert Planning.plan_meal(scope, @mon, "nope", c.chilli_meal.id) == {:error, :not_found}

      c.chilli_meal
      |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
      |> Repo.update!()

      assert Planning.plan_meal(scope, @mon, slots["lunch"].id, c.chilli_meal.id) ==
               {:error, :not_found}
    end

    test "servings must be 1 to 100", %{scope: scope, slots: slots} = c do
      assert {:error, changeset} =
               Planning.plan_meal(scope, @mon, slots["lunch"].id, c.chilli_meal.id, 0)

      assert %{servings: [_]} = errors_on(changeset)

      planned_meal = plan(scope, @mon, slots["lunch"], c.chilli_meal)
      assert {:ok, %PlannedMeal{servings: 5}} = Planning.set_servings(scope, planned_meal.id, 5)
      assert {:error, %Ecto.Changeset{}} = Planning.set_servings(scope, planned_meal.id, 101)
    end

    test "planning a recipe directly reuses or creates its one-recipe meal",
         %{scope: scope, slots: slots, chilli: chilli, salad: salad} do
      # "Chilli night" already holds just the chilli.
      {:ok, planned} = Planning.plan_recipe(scope, @mon, slots["dinner"].id, chilli.id)
      assert Repo.preload(planned, :meal).meal.name == "Chilli night"

      # Nothing holds just the salad: a meal named after it is created, once.
      {:ok, first} = Planning.plan_recipe(scope, @mon, slots["lunch"].id, salad.id)
      {:ok, second} = Planning.plan_recipe(scope, @tue, slots["lunch"].id, salad.id, 2)
      assert first.meal_id == second.meal_id
      assert second.servings == 2
      meal = Meals.get_meal!(scope, first.meal_id)
      assert meal.name == "Salad"
      assert [%{recipe_id: salad_id}] = meal.meal_recipes
      assert salad_id == salad.id
    end

    test "a recipe meal gets a free name when the recipe's is taken",
         %{scope: scope, slots: slots, rice: rice} do
      meal_fixture(scope, %{name: "Rice"})
      meal_fixture(scope, %{name: "rice (2)"})

      {:ok, planned} = Planning.plan_recipe(scope, @mon, slots["dinner"].id, rice.id)
      assert Meals.get_meal!(scope, planned.meal_id).name == "Rice (3)"

      assert Planning.plan_recipe(scope, @mon, slots["dinner"].id, Ecto.UUID.generate()) ==
               {:error, :not_found}
    end

    test "changes, moves and removes planned meals", %{scope: scope, slots: slots} = c do
      planned_meal = plan(scope, @mon, slots["dinner"], c.chilli_meal)
      plan(scope, @tue, slots["lunch"], c.chilli_rice)
      :ok = Households.subscribe(scope)

      assert {:ok, changed} = Planning.change_meal(scope, planned_meal.id, c.chilli_rice.id)
      assert changed.meal_id == c.chilli_rice.id

      next_week = Date.add(@tue, 7)
      {:ok, _} = Planning.skip_slot(scope, next_week, slots["lunch"].id)

      assert {:ok, moved} =
               Planning.move_planned_meal(scope, planned_meal.id, next_week, slots["lunch"].id)

      assert {moved.date, moved.meal_slot_id, moved.position} == {next_week, slots["lunch"].id, 0}
      assert Repo.aggregate(SlotSkip, :count) == 0
      assert_receive {:plan_changed, @mon}
      next_monday = Date.add(@mon, 7)
      assert_receive {:plan_changed, ^next_monday}

      assert {:ok, _} = Planning.remove_planned_meal(scope, planned_meal.id)
      refute Repo.get(PlannedMeal, planned_meal.id)
    end

    test "another household's planned meals can't be touched", %{slots: slots} = c do
      planned_meal = plan(c.scope, @mon, slots["dinner"], c.chilli_meal)
      %{scope: other_scope} = household_fixture()

      assert Planning.set_servings(other_scope, planned_meal.id, 2) == {:error, :not_found}

      assert Planning.change_meal(other_scope, planned_meal.id, c.chilli_rice.id) ==
               {:error, :not_found}

      assert Planning.move_planned_meal(other_scope, planned_meal.id, @tue, slots["dinner"].id) ==
               {:error, :not_found}

      assert Planning.remove_planned_meal(other_scope, planned_meal.id) == {:error, :not_found}
      assert Planning.get_week(other_scope, @mon).planned_meals == []
    end
  end

  describe "skips" do
    test "skip and unskip; refused while meals are planned", %{scope: scope, slots: slots} = c do
      assert {:ok, @mon} = Planning.skip_slot(scope, @mon, slots["breakfast"].id)
      assert {:ok, @mon} = Planning.skip_slot(scope, @mon, slots["breakfast"].id)
      assert Repo.aggregate(SlotSkip, :count) == 1

      assert {:ok, @mon} = Planning.unskip_slot(scope, @mon, slots["breakfast"].id)
      assert Repo.aggregate(SlotSkip, :count) == 0

      plan(scope, @mon, slots["dinner"], c.chilli_meal)
      assert Planning.skip_slot(scope, @mon, slots["dinner"].id) == {:error, :has_meals}
      assert Planning.skip_slot(scope, @mon, Ecto.UUID.generate()) == {:error, :not_found}
    end
  end

  describe "cooked servings (the design's worked examples)" do
    test "planned for 4 with 2 leftover servings cooks 6, ×1.5",
         %{scope: scope, slots: slots} = c do
      monday = plan(scope, @mon, slots["dinner"], c.chilli_meal, 4)
      wednesday = plan(scope, @wed, slots["lunch"], c.chilli_meal, 2)
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      assert cooking(scope, @mon) == [{monday.id, "Chilli", 6, "1.5"}]
    end

    test "planned for 2 with 2 leftover servings cooks the recipe's 4, ×1",
         %{scope: scope, slots: slots} = c do
      monday = plan(scope, @mon, slots["dinner"], c.chilli_meal, 2)
      wednesday = plan(scope, @wed, slots["lunch"], c.chilli_meal, 2)
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      assert cooking(scope, @mon) == [{monday.id, "Chilli", 4, "1"}]
    end

    test "one recipe of a meal can be leftovers while the rest is fresh",
         %{scope: scope, slots: slots} = c do
      monday = plan(scope, @mon, slots["dinner"], c.chilli_rice, 4)
      wednesday = plan(scope, @wed, slots["lunch"], c.chilli_salad, 2)
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      assert Enum.sort(cooking(scope, @mon)) ==
               Enum.sort([
                 {monday.id, "Chilli", 6, "1.5"},
                 {monday.id, "Rice", 4, "2"},
                 {wednesday.id, "Salad", 2, "2"}
               ])
    end

    test "weekend batch cooking feeds meals the following week",
         %{scope: scope, slots: slots} = c do
      # Six portions made on Sunday: two that night, two on Tuesday, two on
      # Thursday of the following week.
      sunday = plan(scope, Date.add(@mon, 6), slots["dinner"], c.chilli_meal, 2)
      tuesday = plan(scope, Date.add(@mon, 8), slots["lunch"], c.chilli_meal, 2)
      thursday = plan(scope, Date.add(@mon, 10), slots["dinner"], c.chilli_meal, 2)
      {:ok, _} = Planning.add_leftover(scope, tuesday.id, sunday.id, c.chilli.id)
      {:ok, _} = Planning.add_leftover(scope, thursday.id, sunday.id, c.chilli.id)

      # Cooked (and shopped for) in the first week; nothing to cook in the next.
      assert cooking(scope, @mon) == [{sunday.id, "Chilli", 6, "1.5"}]
      assert cooking(scope, Date.add(@mon, 7)) == []

      [tuesday_loaded | _] = Planning.get_week(scope, Date.add(@mon, 7)).planned_meals

      assert [%Leftover{source_planned_meal: %PlannedMeal{date: source_date}}] =
               tuesday_loaded.leftovers

      assert source_date == Date.add(@mon, 6)
    end

    test "several leftovers add up; making one fresh again takes it back out",
         %{scope: scope, slots: slots} = c do
      monday = plan(scope, @mon, slots["dinner"], c.chilli_meal, 4)
      tuesday = plan(scope, @tue, slots["lunch"], c.chilli_meal, 1)
      wednesday = plan(scope, @wed, slots["lunch"], c.chilli_meal, 3)
      {:ok, _} = Planning.add_leftover(scope, tuesday.id, monday.id, c.chilli.id)
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      assert cooking(scope, @mon) == [{monday.id, "Chilli", 8, "2"}]

      {:ok, _} = Planning.remove_leftover(scope, wednesday.id, c.chilli.id)

      assert Enum.sort(cooking(scope, @mon)) ==
               Enum.sort([{monday.id, "Chilli", 5, "1.25"}, {wednesday.id, "Chilli", 3, "0.75"}])
    end
  end

  describe "leftover rules" do
    setup %{scope: scope, slots: slots} = c do
      %{
        monday: plan(scope, @mon, slots["dinner"], c.chilli_rice),
        wednesday: plan(scope, @wed, slots["lunch"], c.chilli_salad)
      }
    end

    test "the source must be earlier, at most 14 days, and both meals hold the recipe",
         %{scope: scope, slots: slots, monday: monday, wednesday: wednesday} = c do
      assert Planning.add_leftover(scope, monday.id, wednesday.id, c.chilli.id) ==
               {:error, :not_earlier}

      same_day_lunch = plan(scope, @mon, slots["lunch"], c.chilli_meal)

      assert Planning.add_leftover(scope, same_day_lunch.id, monday.id, c.chilli.id) ==
               {:error, :not_earlier}

      assert Planning.leftover_days() == 14
      fortnight_later = plan(scope, Date.add(@mon, 14), slots["lunch"], c.chilli_meal)
      too_late = plan(scope, Date.add(@mon, 15), slots["lunch"], c.chilli_meal)

      assert {:ok, _} = Planning.add_leftover(scope, fortnight_later.id, monday.id, c.chilli.id)

      assert Planning.add_leftover(scope, too_late.id, monday.id, c.chilli.id) ==
               {:error, :too_far_apart}

      assert Planning.add_leftover(scope, wednesday.id, monday.id, c.rice.id) ==
               {:error, :recipe_not_in_meal}

      assert Planning.add_leftover(scope, wednesday.id, monday.id, c.salad.id) ==
               {:error, :recipe_not_in_meal}

      # Same day, later slot is fine.
      same_day_snack = plan(scope, @mon, slots["snack"], c.chilli_meal)

      assert {:ok, %Leftover{}} =
               Planning.add_leftover(scope, same_day_snack.id, monday.id, c.chilli.id)
    end

    test "no leftovers of leftovers, and each recipe once",
         %{scope: scope, slots: slots, monday: monday, wednesday: wednesday} = c do
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      assert Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id) ==
               {:error, :already_leftover}

      friday = plan(scope, Date.add(@mon, 4), slots["dinner"], c.chilli_meal)

      assert Planning.add_leftover(scope, friday.id, wednesday.id, c.chilli.id) ==
               {:error, :source_is_leftovers}

      # Monday is a source, so it can't itself become leftovers.
      sunday_before = plan(scope, @mon, slots["breakfast"], c.chilli_meal)

      assert Planning.add_leftover(scope, monday.id, sunday_before.id, c.chilli.id) ==
               {:error, :is_a_source}

      assert Planning.add_leftover(scope, wednesday.id, monday.id, "nope") == {:error, :not_found}
    end

    test "moving the source after the eater removes the link",
         %{scope: scope, slots: slots, monday: monday, wednesday: wednesday} = c do
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      # Still earlier: kept.
      {:ok, _} = Planning.move_planned_meal(scope, monday.id, @tue, slots["dinner"].id)
      assert Repo.aggregate(Leftover, :count) == 1

      {:ok, _} =
        Planning.move_planned_meal(scope, monday.id, Date.add(@mon, 4), slots["dinner"].id)

      assert Repo.aggregate(Leftover, :count) == 0
    end

    test "moving the eater more than 14 days after the source removes the link",
         %{scope: scope, slots: slots, monday: monday, wednesday: wednesday} = c do
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      # Into the next week but within 14 days: kept.
      {:ok, _} =
        Planning.move_planned_meal(scope, wednesday.id, Date.add(@wed, 7), slots["lunch"].id)

      assert Repo.aggregate(Leftover, :count) == 1

      {:ok, _} =
        Planning.move_planned_meal(scope, wednesday.id, Date.add(@mon, 15), slots["lunch"].id)

      assert Repo.aggregate(Leftover, :count) == 0
    end

    test "changing a meal to one without the recipe removes the link",
         %{scope: scope, monday: monday, wednesday: wednesday} = c do
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

      {:ok, _} = Planning.change_meal(scope, monday.id, c.chilli_meal.id)
      assert Repo.aggregate(Leftover, :count) == 1

      salad_only = meal_fixture(scope, %{name: "Just salad"}, [c.salad])
      {:ok, _} = Planning.change_meal(scope, monday.id, salad_only.id)
      assert Repo.aggregate(Leftover, :count) == 0
    end

    test "removing either meal removes the link",
         %{scope: scope, monday: monday, wednesday: wednesday} = c do
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)
      {:ok, _} = Planning.remove_planned_meal(scope, monday.id)
      assert Repo.aggregate(Leftover, :count) == 0
      assert Repo.get(PlannedMeal, wednesday.id)
    end
  end

  describe "deleting" do
    test "a slot with planned meals is refused", %{scope: scope, slots: slots} = c do
      plan(scope, @mon, slots["snack"], c.chilli_meal)
      assert Households.delete_meal_slot(scope, slots["snack"].id) == {:error, :in_use}
      assert {:ok, _} = Households.delete_meal_slot(scope, slots["breakfast"].id)
    end

    test "the household takes its whole plan with it", %{scope: scope, slots: slots} = c do
      monday = plan(scope, @mon, slots["dinner"], c.chilli_meal)
      wednesday = plan(scope, @wed, slots["lunch"], c.chilli_meal)
      {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)
      {:ok, _} = Planning.skip_slot(scope, @tue, slots["lunch"].id)

      :ok = Households.delete_household(scope, scope.household.name)

      for schema <- [PlannedMeal, Leftover, SlotSkip],
          do: assert(Repo.aggregate(schema, :count) == 0)
    end
  end
end
