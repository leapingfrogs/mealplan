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
    meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice])
    meal_fixture(scope, %{name: "Soups"}, [quirky, soup, odd])
    meal_fixture(scope, %{name: "Eat out"})
    {:ok, {name, zip}} = Transfer.export(scope)

    %{scope: other} = household_fixture()
    import = Transfer.plan(other, Transfer.read([{name, zip}]))

    assert import.problems == []
    assert Enum.all?(import.recipes ++ import.meals, &(&1.action == :add))

    assert {:ok, %{recipes: %{added: 5}, meals: %{added: 3}}} = Transfer.apply(other, import, %{})
    assert export_files(other) == export_files(scope)
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
