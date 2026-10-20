defmodule Mealplan.MealsTest do
  use Mealplan.DataCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Households
  alias Mealplan.Meals
  alias Mealplan.Meals.Meal
  alias Mealplan.Meals.MealRecipe
  alias Mealplan.Recipes.Recipe

  setup do
    %{scope: scope} = household = household_fixture()

    Map.merge(household, %{
      pasta: recipe_fixture(scope, %{name: "Pasta"}),
      salad: recipe_fixture(scope, %{name: "Green salad"}),
      bread: recipe_fixture(scope, %{name: "Garlic bread"})
    })
  end

  defp recipe_names(scope, meal),
    do: Enum.map(Meals.get_meal!(scope, meal.id).meal_recipes, & &1.recipe.name)

  describe "create_meal/2 and rename_meal/3" do
    test "creates an empty meal and tells the household", %{scope: scope, user: user} do
      :ok = Households.subscribe(scope)

      assert {:ok, %Meal{} = meal} = Meals.create_meal(scope, %{name: " Eat out "})
      assert {meal.name, meal.created_by_id} == {"Eat out", user.id}
      assert_receive {:meal_changed, id} when id == meal.id
      assert Meals.get_meal!(scope, meal.id).meal_recipes == []
    end

    test "names are required and unique per household, ignoring case", %{scope: scope} do
      assert {:error, changeset} = Meals.create_meal(scope, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name

      {:ok, _} = Meals.create_meal(scope, %{name: "Roast"})
      assert {:error, changeset} = Meals.create_meal(scope, %{name: "ROAST"})
      assert "is already a meal" in errors_on(changeset).name

      %{scope: other_scope} = household_fixture()
      assert {:ok, _} = Meals.create_meal(other_scope, %{name: "Roast"})
    end

    test "renames, with the same rules", %{scope: scope} do
      meal = meal_fixture(scope, %{name: "Tea"})
      meal_fixture(scope, %{name: "Supper"})

      assert {:ok, %Meal{name: "Dinner"}} = Meals.rename_meal(scope, meal.id, %{name: "Dinner"})
      assert {:error, changeset} = Meals.rename_meal(scope, meal.id, %{name: "supper"})
      assert "is already a meal" in errors_on(changeset).name
    end
  end

  describe "recipes in a meal" do
    test "are added in order, at most once", %{scope: scope, pasta: pasta, salad: salad} do
      meal = meal_fixture(scope, %{name: "Italian"})
      :ok = Households.subscribe(scope)

      assert {:ok, _} = Meals.add_recipe(scope, meal.id, pasta.id)
      assert {:ok, _} = Meals.add_recipe(scope, meal.id, salad.id)
      assert_receive {:meal_changed, _}
      assert Meals.add_recipe(scope, meal.id, pasta.id) == {:error, :already_in_meal}

      assert recipe_names(scope, meal) == ["Pasta", "Green salad"]
    end

    test "are moved and removed", %{scope: scope} = context do
      meal = meal_fixture(scope, %{}, [context.pasta, context.salad, context.bread])

      assert {:ok, _} = Meals.move_recipe(scope, meal.id, context.bread.id, :up)
      assert recipe_names(scope, meal) == ["Pasta", "Garlic bread", "Green salad"]
      assert Meals.move_recipe(scope, meal.id, context.pasta.id, :up) == {:error, :not_found}

      assert {:ok, _} = Meals.remove_recipe(scope, meal.id, context.pasta.id)
      assert recipe_names(scope, meal) == ["Garlic bread", "Green salad"]
      assert Repo.get(Recipe, context.pasta.id), "the recipe itself stays"
    end

    test "only the household's active recipes can be added", %{scope: scope, pasta: pasta} do
      meal = meal_fixture(scope)
      %{scope: other_scope} = household_fixture()
      theirs = recipe_fixture(other_scope)

      assert Meals.add_recipe(scope, meal.id, theirs.id) == {:error, :not_found}
      assert Meals.add_recipe(scope, meal.id, "not-a-uuid") == {:error, :not_found}

      pasta |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()
      assert Meals.add_recipe(scope, meal.id, pasta.id) == {:error, :not_found}
    end

    test "the database refuses a meal holding another household's recipe", %{scope: scope} do
      meal = meal_fixture(scope)
      %{scope: other_scope} = household_fixture()
      theirs = recipe_fixture(other_scope)

      assert_raise Ecto.ConstraintError, ~r/meal_recipes_recipe_id_fkey/, fn ->
        Repo.insert!(%MealRecipe{
          household_id: scope.household.id,
          meal_id: meal.id,
          recipe_id: theirs.id,
          position: 0
        })
      end
    end

    test "another household's meal can't be changed", %{scope: scope, pasta: pasta} do
      %{scope: other_scope} = household_fixture()
      theirs = meal_fixture(other_scope, %{name: "Theirs"})

      assert Meals.rename_meal(scope, theirs.id, %{name: "Mine"}) == {:error, :not_found}
      assert Meals.add_recipe(scope, theirs.id, pasta.id) == {:error, :not_found}
      assert Meals.remove_recipe(scope, theirs.id, pasta.id) == {:error, :not_found}
      assert Meals.move_recipe(scope, theirs.id, pasta.id, :down) == {:error, :not_found}
      assert_raise Ecto.NoResultsError, fn -> Meals.get_meal!(scope, theirs.id) end
    end
  end

  describe "list_meals/2" do
    test "lists active meals by name with recipe counts, searching meals and recipes",
         %{scope: scope, pasta: pasta, salad: salad} do
      meal_fixture(scope, %{name: "pasta night"}, [pasta, salad])
      meal_fixture(scope, %{name: "Eat out"})
      archived = meal_fixture(scope, %{name: "Old"})
      archived |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()

      %{scope: other_scope} = household_fixture()
      meal_fixture(other_scope, %{name: "Elsewhere"})

      assert [{"Eat out", 0}, {"pasta night", 2}] =
               scope |> Meals.list_meals() |> Enum.map(&{&1.name, &1.recipe_count})

      assert [%{name: "pasta night"}] = Meals.list_meals(scope, "SALAD")
      assert [%{name: "Eat out"}] = Meals.list_meals(scope, "eat")
      assert [] = Meals.list_meals(scope, "50%")
    end
  end

  test "deleting a recipe or the household removes its meal links", %{scope: scope} = context do
    meal = meal_fixture(scope, %{}, [context.pasta, context.salad])

    Repo.delete!(context.pasta)
    assert recipe_names(scope, meal) == ["Green salad"]

    :ok = Households.delete_household(scope, scope.household.name)
    assert Repo.aggregate(Meal, :count) == 0
    assert Repo.aggregate(MealRecipe, :count) == 0
  end
end
