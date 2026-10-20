defmodule Mealplan.ShoppingTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Shopping

  @mon ~D[2026-11-02]
  @wed ~D[2026-11-04]

  setup do
    %{scope: scope} = household = household_fixture()
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1})

    chilli =
      recipe_fixture(scope, %{
        name: "Chilli",
        servings: 4,
        source:
          "Fry @onion{1} in @olive oil{2%tbsp}. Add @kidney beans{400%g} and @?chilli flakes{}."
      })

    rice = recipe_fixture(scope, %{name: "Rice", servings: 4, source: "Boil @rice{300%g}."})

    salad =
      recipe_fixture(scope, %{
        name: "Salad",
        servings: 2,
        source: "Toss @Lettuce{1} with @Olive Oil{50%ml} and @salt{}."
      })

    Map.merge(household, %{
      slots: slots,
      chilli: chilli,
      salad: salad,
      chilli_rice: meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice]),
      chilli_salad: meal_fixture(scope, %{name: "Chilli and salad"}, [chilli, salad])
    })
  end

  defp plan(scope, date, slot, meal, servings) do
    {:ok, planned_meal} = Planning.plan_meal(scope, date, slot.id, meal.id, servings)
    planned_meal
  end

  defp lines(scope, first, last \\ nil) do
    for line <- Shopping.needs(scope, first, last || first), do: {line.name, line.amount}
  end

  # Iteration 1's example: Monday's chilli and rice for 4, with 2 servings of
  # the chilli eaten as leftovers at Wednesday lunch alongside a fresh salad.
  defp leftovers_week(%{scope: scope, slots: slots} = c) do
    monday = plan(scope, @mon, slots["dinner"], c.chilli_rice, 4)
    wednesday = plan(scope, @wed, slots["lunch"], c.chilli_salad, 2)
    {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)
    {monday, wednesday}
  end

  test "scales to cooked servings, leftovers counted in their source", %{scope: scope} = c do
    leftovers_week(c)

    # Chilli cooked for 6 (×1.5), rice for 4, salad for 2; the leftover
    # chilli adds nothing on Wednesday.
    assert lines(scope, @mon, Date.add(@mon, 6)) == [
             {"chilli flakes", "some"},
             {"kidney beans", "600 g"},
             {"Lettuce", "1"},
             {"olive oil", "50 ml + 3 tbsp"},
             {"onion", "2"},
             {"rice", "300 g"},
             {"salt", "some"}
           ]
  end

  test "a source cooked for no more than the recipe makes isn't scaled up", %{scope: scope} = c do
    monday = plan(scope, @mon, c.slots["dinner"], c.chilli_rice, 2)
    wednesday = plan(scope, @wed, c.slots["lunch"], c.chilli_salad, 2)
    {:ok, _} = Planning.add_leftover(scope, wednesday.id, monday.id, c.chilli.id)

    assert {"kidney beans", "400 g"} in lines(scope, @mon)
    assert {"rice", "150 g"} in lines(scope, @mon)
  end

  test "the range decides: leftovers are shopped for with their source", %{scope: scope} = c do
    leftovers_week(c)

    # Monday alone still cooks for Wednesday's leftovers.
    assert {"kidney beans", "600 g"} in lines(scope, @mon)
    # Wednesday alone buys only the salad.
    assert lines(scope, @wed) == [{"Lettuce", "1"}, {"Olive Oil", "50 ml"}, {"salt", "some"}]
    assert lines(scope, Date.add(@mon, 1)) == []
  end

  test "lines merge by key, keep the first name, and say where they come from",
       %{scope: scope} = c do
    {monday, wednesday} = leftovers_week(c)
    [oil] = for line <- Shopping.needs(scope, @mon, @wed), line.key == "olive oil", do: line

    assert oil.name == "olive oil"
    refute oil.optional

    assert [
             %{planned_meal: %{id: from_monday}, recipe: %{name: "Chilli"}, amount: "3 tbsp"},
             %{planned_meal: %{id: from_wednesday}, recipe: %{name: "Salad"}, amount: "50 ml"}
           ] = oil.sources

    assert {from_monday, from_wednesday} == {monday.id, wednesday.id}
    assert hd(oil.sources).planned_meal.meal_slot.name == "Dinner"
  end

  test "an ingredient is optional only when every recipe has it as optional",
       %{scope: scope, slots: slots} = c do
    plan(scope, @mon, slots["dinner"], c.chilli_rice, 4)
    flakes = Enum.find(Shopping.needs(scope, @mon, @mon), &(&1.key == "chilli flake"))
    assert flakes.optional

    spicy =
      recipe_fixture(scope, %{name: "Spicy", servings: 1, source: "Add @chilli flakes{1%tsp}."})

    plan(scope, @mon, slots["lunch"], meal_fixture(scope, %{name: "Spicy"}, [spicy]), 1)
    flakes = Enum.find(Shopping.needs(scope, @mon, @mon), &(&1.key == "chilli flake"))
    refute flakes.optional
    assert flakes.amount == "1 tsp"
  end

  test "repeats in one recipe add up; meals without recipes and skips add nothing",
       %{scope: scope, slots: slots} do
    twice =
      recipe_fixture(scope, %{name: "Twice", servings: 2, source: "@egg{1}, then @Eggs{2}."})

    plan(scope, @mon, slots["breakfast"], meal_fixture(scope, %{name: "Eggs"}, [twice]), 2)
    plan(scope, @mon, slots["dinner"], meal_fixture(scope, %{name: "Eat out"}), 4)
    {:ok, _} = Planning.skip_slot(scope, @mon, slots["lunch"].id)

    assert lines(scope, @mon) == [{"egg", "3"}]
  end

  test "uses the recipes a meal had on the planned date", %{scope: scope, slots: slots} = c do
    today = Planning.today(scope)
    plan(scope, Date.add(today, -1), slots["dinner"], c.chilli_rice, 4)
    plan(scope, today, slots["dinner"], c.chilli_rice, 4)
    {:ok, _} = Meals.remove_recipe(scope, c.chilli_rice.id, c.chilli.id)

    assert {"kidney beans", "400 g"} in lines(scope, Date.add(today, -1))
    assert lines(scope, today) == [{"rice", "300 g"}]
  end

  test "only the household's own plan", c do
    leftovers_week(c)
    %{scope: other} = household_fixture()
    assert Shopping.needs(other, @mon, @wed) == []
  end
end
