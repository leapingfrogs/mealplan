defmodule Mealplan.TransferTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Cooklang
  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Recipes
  alias Mealplan.Transfer
  alias Mealplan.Transfer.CookFile

  doctest CookFile

  defp unzip(binary) do
    {:ok, files} = :zip.unzip(binary, [:memory])
    Map.new(files, fn {path, content} -> {List.to_string(path), content} end)
  end

  setup do
    household_fixture(Mealplan.AccountsFixtures.user_fixture(), %{name: "The Davies"})
  end

  describe "export/1" do
    test "a recipe folder with front matter, and a menu of meals", %{scope: scope} do
      chilli =
        recipe_fixture(scope, %{
          name: "Chilli",
          servings: 4,
          source: "---\nsource: Granny\nservings: 2\n---\n>> serves: 9\nCook @beans{400%g}."
        })

      rice = recipe_fixture(scope, %{name: "Rice", servings: 2})
      chilli_rice = meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice])
      eat_out = meal_fixture(scope, %{name: "Eat out"})
      slots = Map.new(Households.list_meal_slots(scope), &{&1.default_key, &1.id})
      {:ok, _} = Meals.set_slots(scope, chilli_rice.id, [slots["dinner"], slots["lunch"]])
      {:ok, _} = Meals.set_slots(scope, eat_out.id, [slots["dinner"]])

      assert {:ok, {file_name, zip}} = Transfer.export(scope)
      assert file_name == "mealplan-The Davies-#{Planning.today(scope)}.zip"

      files = unzip(zip)

      assert files |> Map.keys() |> Enum.sort() == [
               "meals.menu",
               "recipes/Chilli.cook",
               "recipes/Rice.cook"
             ]

      assert files["recipes/Chilli.cook"] ==
               "---\ntitle: Chilli\nservings: 4\nsource: Granny\n---\nCook @beans{400%g}.\n"

      # It reads back as the same recipe.
      parsed = Cooklang.parse(files["recipes/Chilli.cook"])
      assert parsed.metadata == %{"title" => "Chilli", "servings" => "4", "source" => "Granny"}
      assert [%{name: "beans"}] = parsed.ingredients

      menu = files["meals.menu"]

      assert menu =~
               "= Chilli and rice\n\n> Slots: Lunch, Dinner\n\n@./recipes/Chilli{}\n@./recipes/Rice{}"

      assert menu =~ "= Eat out\n\n> Slots: Dinner\n"

      sections = Cooklang.parse(menu).sections
      assert Enum.map(sections, & &1.name) == ["Chilli and rice", "Eat out"]
      [with_recipes, empty] = sections
      assert [%Cooklang.Note{}, %{items: items}] = with_recipes.blocks

      assert for(%Cooklang.Ingredient{name: name} <- items, do: name) == [
               "./recipes/Chilli",
               "./recipes/Rice"
             ]

      assert empty.blocks == [%Cooklang.Note{text: "Slots: Dinner"}]
    end

    test "unique, safe file names, and references that match them", %{scope: scope} do
      a = recipe_fixture(scope, %{name: "Soup"})
      b = recipe_fixture(scope, %{name: "soup"})
      odd = recipe_fixture(scope, %{name: "Mac & cheese: 1/2 @home"})
      meal_fixture(scope, %{name: "=Lunch="}, [b, odd, a])
      meal_fixture(scope, %{name: "=="})

      {:ok, {_name, zip}} = Transfer.export(scope)
      files = unzip(zip)

      assert "recipes/Mac & cheese- 1-2 -home.cook" in Map.keys(files)
      assert "recipes/Soup.cook" in Map.keys(files)
      assert "recipes/soup (2).cook" in Map.keys(files)
      assert files["meals.menu"] =~ "= Lunch\n"
      assert files["meals.menu"] =~ "= Meal\n"

      references =
        for %Cooklang.Ingredient{name: "./recipes/" <> name} <-
              Cooklang.parse(files["meals.menu"]).ingredients,
            do: name

      assert Enum.all?(references, &Map.has_key?(files, "recipes/#{&1}.cook"))
      assert length(references) == 3
    end

    test "leaves out archived recipes and meals", %{scope: scope} do
      kept = recipe_fixture(scope, %{name: "Kept"})
      old = recipe_fixture(scope, %{name: "Old"})
      meal = meal_fixture(scope, %{name: "Old meal"}, [old])
      [slot | _] = Households.list_meal_slots(scope)
      {:ok, _} = Planning.plan_meal(scope, Date.add(Planning.today(scope), -2), slot.id, meal.id)
      {:ok, :archived} = Recipes.delete_recipe(scope, old)
      {:ok, :archived} = Meals.delete_meal(scope, meal)

      {:ok, {_name, zip}} = Transfer.export(scope)
      files = unzip(zip)

      assert files |> Map.keys() |> Enum.sort() == ["meals.menu", "recipes/#{kept.name}.cook"]
      refute files["meals.menu"] =~ "Old"
    end

    test "an empty household still exports a menu", %{scope: scope} do
      {:ok, {_name, zip}} = Transfer.export(scope)
      assert %{"meals.menu" => "---\nsource: Mealplan\nexported: " <> _} = unzip(zip)
    end

    test "is owner only", %{household: household} do
      %{scope: member_scope} = member_fixture(household)
      assert Transfer.export(member_scope) == {:error, :unauthorized}

      assert Transfer.export(
               Mealplan.Accounts.Scope.for_user(Mealplan.AccountsFixtures.user_fixture())
             ) == {:error, :not_found}
    end
  end

  describe "recipe_file/2" do
    test "one recipe as .cook, owner only, own household only", %{
      scope: scope,
      household: household
    } do
      recipe = recipe_fixture(scope, %{name: "Toast?", servings: 1, source: "@bread{2%slices}"})

      assert {:ok, {"Toast-.cook", "---\ntitle: Toast?\nservings: 1\n---\n@bread{2%slices}\n"}} =
               Transfer.recipe_file(scope, recipe)

      %{scope: member_scope} = member_fixture(household)
      assert Transfer.recipe_file(member_scope, recipe) == {:error, :unauthorized}

      %{scope: other_scope} = household_fixture()
      assert Transfer.recipe_file(other_scope, recipe) == {:error, :not_found}
    end
  end

  describe "CookFile" do
    test "front matter keeps other metadata and drops managed lists and >> lines" do
      source =
        "---\ntags:\n  - quick\nserves: 3\ntitle: Old\nservings:\n  - 2\nsource: Book\n---\n>> Title: x\n>> course: dinner\nMix."

      assert CookFile.with_metadata(source, "New", 5) ==
               "---\ntitle: New\nservings: 5\ntags:\n  - quick\nsource: Book\n---\n>> course: dinner\nMix.\n"
    end

    test "titles YAML would misread are quoted, and read back the same" do
      for title <- [
            "[draft] Soup",
            "Soup: the best",
            "- dash",
            "\"Quoted\" soup",
            "Ends with:",
            "Hash #1",
            ~S("C:\\ path")
          ] do
        text = CookFile.with_metadata("", title, 2)
        assert text =~ ~s(title: ")

        assert Cooklang.parse(text).metadata["title"] == title
      end

      assert CookFile.with_metadata("", "Plain soup", 2) =~ "title: Plain soup\n"
    end

    test "an unclosed front matter block is left in the body" do
      assert CookFile.with_metadata("---\nnot closed", "X", 1) ==
               "---\ntitle: X\nservings: 1\n---\n---\nnot closed\n"
    end

    test "file names never come out empty or hidden" do
      assert CookFile.file_name("  ") == "Untitled"
      assert CookFile.file_name("...hidden") == "hidden"
      assert CookFile.file_name(String.duplicate("a", 150)) == String.duplicate("a", 100)
      assert CookFile.unique_file_names(["A", "a", "A"]) == ["A", "a (2)", "A (3)"]
    end
  end
end
