defmodule MealplanWeb.MealLiveTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Meals

  setup :register_and_log_in_user_with_household

  setup %{scope: scope} do
    %{
      pasta: recipe_fixture(scope, %{name: "Pasta", servings: 2}),
      salad: recipe_fixture(scope, %{name: "Green salad"})
    }
  end

  describe "the meal list" do
    test "creates a meal and opens it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/meals")
      assert has_element?(view, "#meals-empty")

      html = view |> form("#new-meal-form", meal: %{name: " "}) |> render_change()
      assert html =~ "can&#39;t be blank"

      {:ok, show, _html} =
        view
        |> form("#new-meal-form", meal: %{name: "Eat out"})
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(show, "#meal-name", "Eat out")
      assert has_element?(show, "#no-recipes")
    end

    test "refuses a duplicate name", %{conn: conn, scope: scope} do
      meal_fixture(scope, %{name: "Roast"})
      {:ok, view, _html} = live(conn, ~p"/meals")

      html = view |> form("#new-meal-form", meal: %{name: "roast"}) |> render_submit()
      assert html =~ "is already a meal"
    end

    test "lists and searches meals, following other members live",
         %{conn: conn, scope: scope, pasta: pasta} do
      italian = meal_fixture(scope, %{name: "Italian"}, [pasta])
      {:ok, view, _html} = live(conn, ~p"/meals")

      assert has_element?(view, "#meals-#{italian.id}", "1 recipe")

      view |> form("#meal-search", %{q: "pasta"}) |> render_change()
      assert has_element?(view, "#meals-#{italian.id}")

      view |> form("#meal-search", %{q: "zzz"}) |> render_change()
      refute has_element?(view, "#meals-#{italian.id}")
      assert render(view) =~ "No meals match"

      view |> form("#meal-search", %{q: ""}) |> render_change()
      {:ok, added} = Meals.create_meal(scope, %{name: "Takeaway"})
      assert has_element?(view, "#meals-#{added.id}", "No recipes")
    end
  end

  describe "a meal" do
    test "tags the slots it suits, shown in the list", %{conn: conn, scope: scope} do
      meal = meal_fixture(scope, %{name: "Porridge"})
      slots = Map.new(Mealplan.Households.list_meal_slots(scope), &{&1.default_key, &1})
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")

      assert has_element?(view, "#meal-slots", "Tag the slots this meal suits")
      view |> element("#suits-#{slots["breakfast"].id}") |> render_click()
      view |> element("#suits-#{slots["snack"].id}") |> render_click()
      assert has_element?(view, "#suits-#{slots["breakfast"].id}[aria-pressed=true]")

      view |> element("#suits-#{slots["snack"].id}") |> render_click()
      assert has_element?(view, "#suits-#{slots["snack"].id}[aria-pressed=false]")

      {:ok, list, _html} = live(conn, ~p"/meals")
      assert has_element?(list, "#meals-#{meal.id}", "No recipes · Breakfast")

      {:ok, _} =
        Mealplan.Households.rename_meal_slot(scope, slots["breakfast"].id, %{name: "Brekkie"})

      assert has_element?(view, "#suits-#{slots["breakfast"].id}", "Brekkie")
      assert has_element?(list, "#meals-#{meal.id}", "Brekkie")
    end

    test "adds, orders and removes recipes", %{conn: conn, scope: scope} = context do
      meal = meal_fixture(scope, %{name: "Italian"})
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")

      view |> element("#candidate-#{context.pasta.id} button") |> render_click()
      view |> element("#candidate-#{context.salad.id} button") |> render_click()
      refute has_element?(view, "#candidate-#{context.pasta.id}")
      assert has_element?(view, "#meal-recipe-#{context.pasta.id}", "Serves 2")
      assert has_element?(view, "#no-candidates")

      view
      |> element("#meal-recipe-#{context.salad.id} button[phx-value-direction=up]")
      |> render_click()

      assert names(scope, meal) == ["Green salad", "Pasta"]

      view |> element("#meal-recipe-#{context.salad.id} button", "Remove") |> render_click()
      refute has_element?(view, "#meal-recipe-#{context.salad.id}")
      assert has_element?(view, "#candidate-#{context.salad.id}")
    end

    test "searches recipes to add", %{conn: conn, scope: scope} = context do
      meal = meal_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")

      view |> form("#recipe-picker", %{q: "sal"}) |> render_change()
      assert has_element?(view, "#candidate-#{context.salad.id}")
      refute has_element?(view, "#candidate-#{context.pasta.id}")

      view |> form("#recipe-picker", %{q: "zzz"}) |> render_change()
      assert has_element?(view, "#no-candidates", "No recipes match")
    end

    test "renames", %{conn: conn, scope: scope} do
      meal = meal_fixture(scope, %{name: "Tea"})
      meal_fixture(scope, %{name: "Supper"})
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")

      view |> element("#rename-meal") |> render_click()
      html = view |> form("#rename-meal-form", meal: %{name: "supper"}) |> render_submit()
      assert html =~ "is already a meal"

      view |> form("#rename-meal-form", meal: %{name: "Dinner"}) |> render_submit()
      assert has_element?(view, "#meal-name", "Dinner")

      view |> element("#rename-meal") |> render_click()
      view |> element("#rename-meal-form button", "Cancel") |> render_click()
      assert has_element?(view, "#meal-name", "Dinner")
    end

    test "follows changes by other members", %{conn: conn, scope: scope, pasta: pasta} do
      meal = meal_fixture(scope, %{name: "Italian"})
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")

      %{scope: member_scope} = member_fixture(scope.household)
      {:ok, _} = Meals.add_recipe(member_scope, meal.id, pasta.id)
      assert has_element?(view, "#meal-recipe-#{pasta.id}")

      {:ok, _} = Mealplan.Recipes.update_recipe(member_scope, pasta, %{name: "Penne"})
      assert has_element?(view, "#meal-recipe-#{pasta.id}", "Penne")
    end

    test "flashes when a change fails", %{conn: conn, scope: scope, pasta: pasta} do
      meal = meal_fixture(scope, %{}, [pasta])
      {:ok, view, _html} = live(conn, ~p"/meals/#{meal}")

      html = render_click(view, "add", %{"id" => pasta.id})
      assert html =~ "Couldn&#39;t add that recipe"
    end

    test "another household's meal is not found", %{conn: conn} do
      %{scope: other_scope} = household_fixture()
      theirs = meal_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/meals/#{theirs}") end
    end
  end

  defp names(scope, meal),
    do: Enum.map(Meals.get_meal!(scope, meal.id).meal_recipes, & &1.recipe.name)
end
