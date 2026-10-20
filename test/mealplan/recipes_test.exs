defmodule Mealplan.RecipesTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Households
  alias Mealplan.Recipes
  alias Mealplan.Recipes.Recipe
  alias Mealplan.Recipes.RecipeIngredient

  @pancakes """
  ---
  servings: 4
  ---
  Whisk @flour{250%grams}, @Eggs{2} and @milk{1/2%l} with a pinch of @salt.

  Fry in #pan{} for ~{2%minutes}; top with @?lemon{} if you like.
  """

  setup do
    household_fixture(Mealplan.AccountsFixtures.user_fixture(), %{usually_feeding: 3})
  end

  describe "create_recipe/2" do
    test "saves the recipe and its normalised ingredient rows", %{scope: scope, user: user} do
      :ok = Households.subscribe(scope)

      assert {:ok, %Recipe{} = recipe} =
               Recipes.create_recipe(scope, %{
                 name: " Pancakes ",
                 servings: "4",
                 source: @pancakes
               })

      assert recipe.name == "Pancakes"
      assert recipe.created_by_id == user.id
      assert_receive {:recipe_changed, id} when id == recipe.id

      assert [flour, eggs, milk, salt, lemon] = recipe.ingredients
      assert {flour.key, flour.canonical_unit, flour.dimension} == {"flour", "g", :mass}
      assert Decimal.eq?(flour.quantity, 250) and flour.scalable
      assert {eggs.name, eggs.key, eggs.dimension} == {"Eggs", "egg", :count}
      assert Decimal.eq?(milk.quantity, "0.5") and milk.canonical_unit == "l"
      assert {salt.quantity, salt.quantity_text, salt.scalable} == {nil, nil, false}
      assert lemon.optional
      assert Enum.map(recipe.ingredients, & &1.position) == [0, 1, 2, 3, 4]
    end

    test "a recipe can be just a name and servings", %{scope: scope} do
      assert {:ok, recipe} = Recipes.create_recipe(scope, %{name: "Toast", servings: 1})
      assert recipe.source == ""
      assert recipe.ingredients == []
    end

    test "text quantities are kept as written", %{scope: scope} do
      recipe = recipe_fixture(scope, %{source: "@thyme{few%sprigs}"})

      assert [%RecipeIngredient{quantity: nil, quantity_text: "few", canonical_unit: "sprig"}] =
               recipe.ingredients
    end

    test "validates name, servings and source length", %{scope: scope} do
      assert {:error, changeset} = Recipes.create_recipe(scope, %{name: " ", servings: 0})
      assert %{name: ["can't be blank"], servings: [_]} = errors_on(changeset)

      too_long = String.duplicate("a", 50_001)

      assert {:error, changeset} =
               Recipes.create_recipe(scope, %{name: "X", servings: 2, source: too_long})

      assert %{source: [_]} = errors_on(changeset)
    end

    test "parse warnings never stop saving", %{scope: scope} do
      assert {:ok, recipe} =
               Recipes.create_recipe(scope, %{name: "Odd", servings: 2, source: "[- never closed"})

      assert recipe.ingredients == []
    end

    test "browser line endings are normalised", %{scope: scope} do
      recipe = recipe_fixture(scope, %{source: "One.\r\n\r\nTwo."})
      assert recipe.source == "One.\n\nTwo."
    end

    test "new_recipe/1 serves the household's usual number", %{scope: scope} do
      assert %Recipe{servings: 3} = Recipes.new_recipe(scope)
    end
  end

  describe "update_recipe/3" do
    test "rebuilds the ingredient rows from the new source", %{scope: scope} do
      recipe = recipe_fixture(scope, %{source: @pancakes})

      assert {:ok, updated} =
               Recipes.update_recipe(scope, recipe, %{source: "Toast @bread{2%slices}."})

      assert [%RecipeIngredient{key: "bread", canonical_unit: "slice"}] = updated.ingredients
      assert Repo.aggregate(RecipeIngredient, :count) == 1
    end

    test "clearing the source removes the ingredients; a name is still required",
         %{scope: scope} do
      recipe = recipe_fixture(scope, %{source: @pancakes})

      assert {:ok, updated} = Recipes.update_recipe(scope, recipe, %{"source" => ""})
      assert {updated.source, updated.ingredients} == {"", []}

      assert {:error, changeset} = Recipes.update_recipe(scope, updated, %{"name" => nil})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "refuses another household's recipe", %{scope: scope} do
      %{scope: other_scope} = household_fixture()
      theirs = recipe_fixture(other_scope, %{name: "Theirs"})

      assert Recipes.update_recipe(scope, theirs, %{name: "Mine"}) == {:error, :not_found}
      assert Repo.reload!(theirs).name == "Theirs"
    end
  end

  describe "list_recipes/2" do
    setup %{scope: scope} do
      recipe_fixture(scope, %{name: "pancakes", source: @pancakes})

      recipe_fixture(scope, %{
        name: "Beans on toast",
        source: "@baked beans{1%tin} on @bread{2%slices}"
      })

      recipe_fixture(scope, %{name: "Apple 50% off_sale"})
      :ok
    end

    test "lists by name, ignoring case, with distinct ingredient counts", %{scope: scope} do
      assert [{"Apple 50% off_sale", 0}, {"Beans on toast", 2}, {"pancakes", 5}] =
               scope |> Recipes.list_recipes() |> Enum.map(&{&1.name, &1.ingredient_count})
    end

    test "searches names and ingredients, ignoring case", %{scope: scope} do
      names = fn search -> scope |> Recipes.list_recipes(search) |> Enum.map(& &1.name) end

      assert names.("TOAST") == ["Beans on toast"]
      assert names.("bread") == ["Beans on toast"]
      assert names.("egg") == ["pancakes"]
      assert names.("eggs") == ["pancakes"]
      assert names.("  ") == ["Apple 50% off_sale", "Beans on toast", "pancakes"]
      assert names.("nothing") == []
    end

    test "treats % and _ literally", %{scope: scope} do
      assert [%{name: "Apple 50% off_sale"}] = Recipes.list_recipes(scope, "50%")
      assert [%{name: "Apple 50% off_sale"}] = Recipes.list_recipes(scope, "f_s")
      assert [] = Recipes.list_recipes(scope, "o_t")
    end

    test "only lists the scope's household's active recipes", %{scope: scope} do
      %{scope: other_scope} = household_fixture()
      recipe_fixture(other_scope, %{name: "Elsewhere"})

      archived = recipe_fixture(scope, %{name: "Archived"})
      archived |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()

      names = scope |> Recipes.list_recipes() |> Enum.map(& &1.name)
      refute "Elsewhere" in names
      refute "Archived" in names
    end
  end

  describe "get_recipe!/2" do
    test "gets the household's recipe with ingredients, and nothing else", %{scope: scope} do
      recipe = recipe_fixture(scope, %{source: @pancakes})
      assert %Recipe{ingredients: [_ | _]} = Recipes.get_recipe!(scope, recipe.id)

      %{scope: other_scope} = household_fixture()
      assert_raise Ecto.NoResultsError, fn -> Recipes.get_recipe!(other_scope, recipe.id) end
    end
  end

  test "deleting the household deletes its recipes", %{scope: scope, household: household} do
    recipe_fixture(scope, %{source: @pancakes})
    :ok = Households.delete_household(scope, household.name)

    assert Repo.aggregate(Recipe, :count) == 0
    assert Repo.aggregate(RecipeIngredient, :count) == 0
  end
end
