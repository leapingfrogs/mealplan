defmodule MealplanWeb.ExportControllerTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  describe "GET /household/export" do
    setup :register_and_log_in_user_with_household

    test "sends the owner a zip of recipes and meals", %{conn: conn, scope: scope} do
      recipe_fixture(scope, %{name: "Chilli", servings: 4})

      conn = get(conn, ~p"/household/export")

      assert response_content_type(conn, :zip) =~ "application/zip"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~s(attachment; filename="mealplan-)

      {:ok, files} = :zip.unzip(response(conn, 200), [:memory])

      assert files |> Enum.map(&(&1 |> elem(0) |> List.to_string())) |> Enum.sort() == [
               "meals.menu",
               "recipes/Chilli.cook"
             ]
    end

    test "is a 404 for members and people without a household", %{scope: scope} do
      %{user: member} = member_fixture(scope.household)
      conn = build_conn() |> log_in_user(member) |> get(~p"/household/export")
      assert response(conn, 404)

      %{conn: lone} = register_and_log_in_user(%{conn: build_conn()})
      assert lone |> get(~p"/household/export") |> response(404)
    end

    test "needs a login" do
      assert build_conn() |> get(~p"/household/export") |> redirected_to() == ~p"/users/log-in"
    end
  end

  describe "GET /recipes/:id/download" do
    setup :register_and_log_in_user_with_household

    test "sends one recipe as .cook", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope, %{name: "Toast", servings: 1, source: "@bread{2%slices}"})

      conn = get(conn, ~p"/recipes/#{recipe}/download")

      assert response(conn, 200) == "---\ntitle: Toast\nservings: 1\n---\n@bread{2%slices}\n"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~s(filename="Toast.cook")
    end

    test "is a 404 for other households, members, and bad ids", %{conn: conn, scope: scope} do
      %{scope: other_scope} = household_fixture()
      theirs = recipe_fixture(other_scope)
      assert conn |> get(~p"/recipes/#{theirs}/download") |> response(404)
      assert conn |> get(~p"/recipes/not-an-id/download") |> response(404)

      mine = recipe_fixture(scope)
      %{user: member} = member_fixture(scope.household)

      assert build_conn()
             |> log_in_user(member)
             |> get(~p"/recipes/#{mine}/download")
             |> response(404)
    end
  end

  describe "the buttons" do
    setup :register_and_log_in_user_with_household

    test "owners see Export and Download; members don't", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope)
      {:ok, household, _html} = live(conn, ~p"/household")
      assert has_element?(household, "#export-household[href='/household/export']")
      {:ok, page, _html} = live(conn, ~p"/recipes/#{recipe}")
      assert has_element?(page, "#download-recipe")

      %{user: member} = member_fixture(scope.household)
      member_conn = log_in_user(build_conn(), member)
      {:ok, household, _html} = live(member_conn, ~p"/household")
      refute has_element?(household, "#export-household")
      {:ok, page, _html} = live(member_conn, ~p"/recipes/#{recipe}")
      refute has_element?(page, "#download-recipe")
    end
  end
end
