defmodule Mealplan.Transfer.ImporterTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Recipes
  alias Mealplan.Transfer
  alias Mealplan.Transfer.Import
  alias Mealplan.Transfer.ImportItem

  defp unzip(binary) do
    {:ok, files} = :zip.unzip(binary, [:memory])
    Map.new(files, fn {path, content} -> {List.to_string(path), content} end)
  end

  defp export_files(scope) do
    {:ok, {_name, zip}} = Transfer.export(scope)
    unzip(zip)
  end

  defp plan(scope, uploads), do: Transfer.plan(scope, Transfer.read(uploads))

  defp names(scope), do: scope |> Recipes.list_recipes() |> Enum.map(&{&1.name, &1.servings})
  defp meal_names(scope), do: scope |> Meals.list_meals() |> Enum.map(& &1.name)

  defp meal_recipes(scope, name) do
    meal = Enum.find(Meals.list_meals(scope), &(&1.name == name))
    scope |> Meals.get_meal!(meal.id) |> Map.fetch!(:meal_recipes) |> Enum.map(& &1.recipe.name)
  end

  setup do
    household_fixture(Mealplan.AccountsFixtures.user_fixture(), %{usually_feeding: 3})
  end

  test "export, then import into a new household, round-trips exactly", %{scope: scope} do
    chilli =
      recipe_fixture(scope, %{
        name: "Chilli",
        servings: 4,
        source: "---\nsource: Granny\n---\nCook @beans{400%g}."
      })

    rice = recipe_fixture(scope, %{name: "Rice", servings: 2, source: "Boil @rice{150%g}."})
    soup = recipe_fixture(scope, %{name: "Soup"})
    quirky = recipe_fixture(scope, %{name: "soup", servings: 6})
    odd = recipe_fixture(scope, %{name: ~s("Quoted": #1 / 2)})
    chilli_rice = meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice])
    meal_fixture(scope, %{name: "Soups"}, [quirky, soup, odd])
    eat_out = meal_fixture(scope, %{name: "Eat out"})
    slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1.id})
    {:ok, _} = Meals.set_slots(scope, chilli_rice.id, [slots["dinner"], slots["lunch"]])
    {:ok, _} = Meals.set_slots(scope, eat_out.id, [slots["dinner"]])
    {:ok, {name, zip}} = Transfer.export(scope)

    %{scope: other} = household_fixture()
    import = Transfer.plan(other, Transfer.read([{name, zip}]))

    assert import.problems == []
    assert Enum.all?(import.recipes ++ import.meals, &(&1.action == :add))

    assert {:ok, %{recipes: %{added: 5}, meals: %{added: 3}}} = Transfer.apply(other, import, %{})
    assert export_files(other) == export_files(scope)
    assert export_files(other)["meals.menu"] =~ "> Slots: Lunch, Dinner"
  end

  describe "plan/2" do
    test "matches by name, ignoring case, and defaults servings", %{scope: scope} do
      ours = recipe_fixture(scope, %{name: "Chilli"})
      meal_fixture(scope, %{name: "Tea"})

      import =
        plan(scope, [
          {"CHILLI.cook", "Cook."},
          {"big.cook", "---\nservings: 500\n---\n"},
          {"m.menu", "= tea\n\n= Lunch"}
        ])

      assert [
               %ImportItem{key: "recipe-0", action: :skip, existing: %{id: id}, servings: 3},
               %ImportItem{key: "recipe-1", action: :add, existing: nil, servings: 100}
             ] = import.recipes

      assert id == ours.id

      assert [%ImportItem{action: :skip, existing: %{name: "Tea"}}, %ImportItem{action: :add}] =
               import.meals
    end

    test "resolves references: imported by path or name, then ours, else missing", %{scope: scope} do
      ours = recipe_fixture(scope, %{name: "Mac & cheese: deluxe"})
      gravy = recipe_fixture(scope, %{name: "Gravy"})

      menu = """
      = Sunday
      @./mains/roast{} @./desserts/crumble.cook{} @Yorkshire puddings{}
      @./sides/gravy{} @./Mac & cheese- deluxe{} @Gravy{} @./nowhere/thing{} @Nothing{}
      """

      import =
        plan(scope, [
          {"box.zip",
           zip([
             {"family/mains/roast.cook", "Roast."},
             {"family/desserts/Crumble.cook", "Bake."},
             {"family/yorkshires.cook", "---\ntitle: Yorkshire puddings\n---\n"},
             {"family/menu.menu", menu}
           ])}
        ])

      [%ImportItem{references: references}] = import.meals

      references =
        Enum.map(references, fn
          {:existing, recipe} -> {:existing, recipe.id}
          other -> other
        end)

      assert references == [
               {:imported, "recipe-0"},
               {:imported, "recipe-1"},
               {:imported, "recipe-2"},
               {:existing, gravy.id},
               {:existing, ours.id},
               {:existing, gravy.id},
               {:missing, "nowhere/thing"},
               {:missing, "Nothing"}
             ]
    end
  end

  defp zip(entries) do
    files = for {path, content} <- entries, do: {String.to_charlist(path), content}
    {:ok, {_name, binary}} = :zip.create(~c"t.zip", files, [:memory])
    binary
  end

  describe "slot tags" do
    setup %{scope: scope} do
      {:ok, brunch} = Households.create_meal_slot(scope, %{name: "Brunch"})
      slots = scope |> Households.list_meal_slots() |> Map.new(&{&1.name, &1.id})
      ours = meal_fixture(scope, %{name: "Chilli night"})
      {:ok, _} = Meals.set_slots(scope, ours.id, [slots["Breakfast"]])

      menu = """
      = Chilli night

      > Slots: dinner

      = Picnic

      > Serve cold.

      > SLOTS:  lunch , Elevenses,, LUNCH ,brunch

      = Eat out
      """

      %{slots: slots, brunch: brunch, ours: ours, import: plan(scope, [{"m.menu", menu}])}
    end

    defp meal_slots(scope, name) do
      meal = Enum.find(Meals.list_meals(scope), &(&1.name == name))
      Enum.map(meal.slots, & &1.name)
    end

    test "match our active slots ignoring case and spaces; the rest are kept to show", c do
      [chilli, picnic, eat_out] = c.import.meals
      assert picnic.imported.slot_names == ["lunch", "Elevenses", "brunch"]
      assert {chilli.slot_ids, chilli.unmatched_slots} == {[c.slots["Dinner"]], []}

      assert {picnic.slot_ids, picnic.unmatched_slots} ==
               {[c.slots["Lunch"], c.brunch.id], ["Elevenses"]}

      assert {eat_out.slot_ids, eat_out.unmatched_slots} == {[], []}
    end

    test "add and keep both tag the new meal; replace sets ours; skip leaves ours alone",
         %{scope: scope} = c do
      import = Transfer.choose_slots(c.import, "meal-2", [c.slots["Dinner"], c.slots["Dinner"]])
      assert {:ok, _summary} = Transfer.apply(scope, import, %{})
      assert meal_slots(scope, "Picnic") == ["Lunch", "Brunch"]
      assert meal_slots(scope, "Eat out") == ["Dinner"]
      assert meal_slots(scope, "Chilli night") == ["Breakfast"]

      assert {:ok, _summary} = Transfer.apply(scope, c.import, %{"meal-0" => "keep_both"})
      assert meal_slots(scope, "Chilli night (2)") == ["Dinner"]

      assert {:ok, _summary} = Transfer.apply(scope, c.import, %{"meal-0" => "replace"})
      assert meal_slots(scope, "Chilli night") == ["Dinner"]
    end

    test "a meal without a slots note starts with our tags, so replacing keeps them",
         %{scope: scope} = c do
      import = plan(scope, [{"m.menu", "= chilli NIGHT\n\n> Serve hot."}])
      [item] = import.meals
      assert {item.action, item.slot_ids} == {:skip, [c.slots["Breakfast"]]}

      assert {:ok, _summary} = Transfer.apply(scope, import, %{"meal-0" => "replace"})
      assert meal_slots(scope, "Chilli night") == ["Breakfast"]

      assert {:ok, _summary} = Transfer.apply(scope, import, %{"meal-0" => "keep_both"})
      assert meal_slots(scope, "chilli NIGHT (2)") == ["Breakfast"]

      cleared = Transfer.choose_slots(import, "meal-0", [])
      assert {:ok, _summary} = Transfer.apply(scope, cleared, %{"meal-0" => "replace"})
      assert meal_slots(scope, "Chilli night") == []
    end

    test "a slot deleted since the preview is dropped", %{scope: scope} = c do
      {:ok, _} = Households.delete_meal_slot(scope, c.brunch.id)
      assert {:ok, _summary} = Transfer.apply(scope, c.import, %{})
      assert meal_slots(scope, "Picnic") == ["Lunch"]
    end
  end

  describe "apply/3" do
    setup %{scope: scope} do
      chilli = recipe_fixture(scope, %{name: "Chilli", servings: 4, source: "Ours."})
      rice = recipe_fixture(scope, %{name: "Rice", servings: 2})
      meal = meal_fixture(scope, %{name: "Chilli night"}, [chilli])

      uploads = [
        {"Chilli.cook", "---\nservings: 6\n---\nTheirs."},
        {"Salad.cook", "Toss."},
        {"m.menu", "= Chilli night\n@./Chilli{} @./Salad{}\n\n= Rice bowl\n@./Rice{} @./Salad{}"}
      ]

      %{chilli: chilli, rice: rice, meal: meal, import: plan(scope, uploads)}
    end

    test "defaults: matches are skipped, new ones added and linked to ours",
         %{scope: scope} = c do
      :ok = Households.subscribe(scope)

      assert {:ok, %{recipes: recipes, meals: meals}} = Transfer.apply(scope, c.import, %{})
      assert recipes == %{added: 1, replaced: 0, skipped: 1, left_out: 0}
      assert meals == %{added: 1, replaced: 0, skipped: 1, left_out: 0}

      assert Repo.reload!(c.chilli).source == "Ours."
      assert meal_recipes(scope, "Chilli night") == ["Chilli"]
      assert meal_recipes(scope, "Rice bowl") == ["Rice", "Salad"]
      assert_receive {:recipe_changed, _id}
      assert_receive {:meal_changed, _id}
    end

    test "replace: our recipe takes the new source and servings; our meal the new recipes",
         %{scope: scope} = c do
      [slot | _] = Households.list_meal_slots(scope)
      past = Date.add(Planning.today(scope), -2)
      {:ok, _} = Planning.plan_meal(scope, past, slot.id, c.meal.id)

      choices = %{"recipe-0" => "replace", "meal-0" => "replace"}

      assert {:ok, %{recipes: %{replaced: 1}, meals: %{replaced: 1}}} =
               Transfer.apply(scope, c.import, choices)

      chilli = Repo.reload!(c.chilli)
      assert {chilli.servings, chilli.source} == {6, "---\nservings: 6\n---\nTheirs."}
      assert meal_recipes(scope, "Chilli night") == ["Chilli", "Salad"]
      assert "Chilli" in (scope |> Meals.recipes_on(c.meal.id, past) |> Enum.map(& &1.name))
    end

    test "keep both: copies with free names", %{scope: scope} = c do
      choices = %{"recipe-0" => :keep_both, "meal-0" => "keep_both"}
      assert {:ok, _summary} = Transfer.apply(scope, c.import, choices)

      assert {"Chilli (2)", 6} in names(scope)
      assert "Chilli night (2)" in meal_names(scope)
      assert meal_recipes(scope, "Chilli night (2)") == ["Chilli (2)", "Salad"]
      assert meal_recipes(scope, "Chilli night") == ["Chilli"]
    end

    test "leave out: nothing for it, and meals drop the reference", %{scope: scope} = c do
      choices = %{"recipe-1" => "leave_out", "meal-0" => "leave_out"}

      assert {:ok, %{recipes: %{left_out: 1}, meals: %{left_out: 1, added: 1}}} =
               Transfer.apply(scope, c.import, choices)

      refute Enum.any?(names(scope), &(elem(&1, 0) == "Salad"))
      assert meal_recipes(scope, "Rice bowl") == ["Rice"]
    end

    test "choices that don't fit an item are ignored", %{scope: scope} = c do
      choices = %{
        "recipe-1" => "replace",
        "recipe-0" => "add",
        "meal-1" => "explode",
        "nope" => "add"
      }

      assert {:ok, %{recipes: %{added: 1, skipped: 1}}} = Transfer.apply(scope, c.import, choices)
    end

    test "two imported meals with one name both arrive", %{scope: scope} do
      import = plan(scope, [{"a.menu", "= Picnic\n\n= picnic"}])
      assert {:ok, %{meals: %{added: 2}}} = Transfer.apply(scope, import, %{})
      assert Enum.sort(meal_names(scope)) == ["Chilli night", "Picnic", "picnic (2)"]
    end

    test "all or nothing", %{scope: scope, rice: rice} = c do
      # Rice is archived after the preview was made, so linking it fails.
      [slot | _] = Households.list_meal_slots(scope)

      {:ok, _} =
        Planning.plan_meal(scope, Date.add(Planning.today(scope), -1), slot.id, c.meal.id)

      rice |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()

      assert {:error, :not_found} = Transfer.apply(scope, c.import, %{})
      refute Enum.any?(names(scope), &(elem(&1, 0) == "Salad"))
      refute "Rice bowl" in meal_names(scope)
    end

    test "owner only, and at most 5 imports an hour", %{scope: scope, household: household} = c do
      %{scope: member_scope} = member_fixture(household)
      assert Transfer.apply(member_scope, c.import, %{}) == {:error, :unauthorized}

      empty = %Import{}
      for _ <- 1..5, do: assert({:ok, _} = Transfer.apply(scope, empty, %{}))
      assert Transfer.apply(scope, empty, %{}) == {:error, :rate_limited}

      lone = Mealplan.Accounts.Scope.for_user(Mealplan.AccountsFixtures.user_fixture())
      assert Transfer.apply(lone, empty, %{}) == {:error, :unauthorized}
    end
  end
end
