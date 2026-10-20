defmodule MealplanWeb.RecipeLiveTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Recipes

  @source """
  Whisk @eggs{2} with @milk{300%ml}, then fry in a #pan for ~{2%minutes}.

  Serve.
  """

  test "requires a household", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    assert {:error, {:redirect, %{to: "/welcome"}}} = live(conn, ~p"/recipes")
  end

  describe "with a household" do
    setup :register_and_log_in_user_with_household

    test "lists and searches recipes", %{conn: conn, scope: scope} do
      pancakes = recipe_fixture(scope, %{name: "Pancakes", source: @source})
      toast = recipe_fixture(scope, %{name: "Toast", source: "@bread{2%slices}"})

      {:ok, view, _html} = live(conn, ~p"/recipes")
      assert has_element?(view, "#recipes-#{pancakes.id}", "Pancakes")
      assert has_element?(view, "#recipes-#{pancakes.id}", "2 ingredients")
      assert has_element?(view, "#recipes-#{toast.id}")

      view |> form("#recipe-search", %{q: "milk"}) |> render_change()
      assert has_element?(view, "#recipes-#{pancakes.id}")
      refute has_element?(view, "#recipes-#{toast.id}")

      view |> form("#recipe-search", %{q: "zzz"}) |> render_change()
      assert render(view) =~ "No recipes match"
    end

    test "creates a recipe, previewing it first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      view
      |> form("#recipe-form", recipe: %{name: "Pancakes", source: @source})
      |> render_change()

      assert has_element?(view, "#ingredient-summary", "eggs")
      assert has_element?(view, "#ingredient-summary", "300 ml")

      view |> element("#tab-preview") |> render_click()
      assert has_element?(view, "#preview-panel:not(.hidden) #preview-ingredients", "milk")
      assert has_element?(view, "#preview-method", "Serve.")

      {:ok, show, _html} =
        view
        |> form("#recipe-form", recipe: %{name: "Pancakes", servings: 2, source: @source})
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(show, "#recipe-name", "Pancakes")
      assert has_element?(show, "#ingredients", "milk")
      assert has_element?(show, "#cookware", "pan")
      assert has_element?(show, "#method", "2 minutes")
    end

    test "new recipes default to the household's usual servings", %{
      conn: conn,
      household: household
    } do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")
      assert has_element?(view, "#recipe_servings[value='#{household.usually_feeding}']")
    end

    test "shows validation errors and warnings, but saves despite warnings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      html = view |> form("#recipe-form", recipe: %{name: "", servings: 0}) |> render_submit()
      assert html =~ "can&#39;t be blank"

      view
      |> form("#recipe-form", recipe: %{name: "Odd", servings: 2, source: "[- open"})
      |> render_change()

      assert has_element?(view, "#source-warnings", "never closed")

      assert {:ok, _show, _html} =
               view
               |> form("#recipe-form", recipe: %{name: "Odd", servings: 2, source: "[- open"})
               |> render_submit()
               |> follow_redirect(conn)
    end

    test "edits a recipe; its page and list follow live", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope, %{name: "Pancakes", source: @source})
      {:ok, show, _html} = live(conn, ~p"/recipes/#{recipe}")
      {:ok, list, _html} = live(conn, ~p"/recipes")

      {:ok, edit, _html} = live(conn, ~p"/recipes/#{recipe}/edit")
      assert has_element?(edit, "#recipe_name[value='Pancakes']")

      edit
      |> form("#recipe-form", recipe: %{name: "Crêpes", source: "Fry @batter{1%l}."})
      |> render_submit()

      assert_redirect(edit, ~p"/recipes/#{recipe}")
      assert has_element?(show, "#recipe-name", "Crêpes")
      assert has_element?(show, "#ingredients", "batter")
      refute has_element?(show, "#ingredients", "eggs")
      assert has_element?(list, "#recipes-#{recipe.id}", "Crêpes")
    end

    test "warns an editor when someone else saves the same recipe", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope, %{name: "Pancakes"})
      {:ok, edit, _html} = live(conn, ~p"/recipes/#{recipe}/edit")
      refute has_element?(edit, "#changed-elsewhere")

      %{scope: member_scope} = member_fixture(scope.household)
      {:ok, _} = Recipes.update_recipe(member_scope, recipe, %{servings: 6})

      assert has_element?(edit, "#changed-elsewhere")
    end

    test "an empty recipe says so", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope, %{name: "Toast"})
      {:ok, show, _html} = live(conn, ~p"/recipes/#{recipe}")
      assert has_element?(show, "#empty-recipe")
    end

    test "another household's recipe is not found", %{conn: conn} do
      %{scope: other_scope} = household_fixture()
      theirs = recipe_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/recipes/#{theirs}") end
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/recipes/#{theirs}/edit") end
    end
  end
end
