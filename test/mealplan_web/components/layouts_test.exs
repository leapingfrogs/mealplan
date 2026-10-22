defmodule MealplanWeb.LayoutsTest do
  use MealplanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "with a household" do
    setup :register_and_log_in_user_with_household

    test "the tab bar and sidebar list the sections and mark the current one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes")

      for nav <- ["#tab-bar", "#sidebar nav"] do
        for {id, path} <- [
              plan: "/plan",
              recipes: "/recipes",
              meals: "/meals",
              shopping: "/shopping",
              household: "/household"
            ] do
          assert has_element?(view, "#{nav} a[href='#{path}']"), "#{nav} #{id}"
        end

        assert has_element?(view, "#{nav} a[aria-current=page][href='/recipes']")
        assert has_element?(view, "#{nav} a[aria-current=page]", "Recipes")
        refute has_element?(view, "#{nav} a[aria-current=page][href='/plan']")
      end

      {:ok, view, _html} = live(conn, ~p"/shopping")
      assert has_element?(view, "#tab-bar a[aria-current=page][href='/shopping']")
    end

    test "the household name, account, theme and log out are in the shell",
         %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/plan")

      assert has_element?(view, "#household-name", scope.household.name)

      for menu <- ["#sidebar", "#account-dropdown"] do
        assert has_element?(view, "#{menu}", scope.user.email)
        assert has_element?(view, "#{menu} a[href='/users/settings']", "Account")
        assert has_element?(view, "#{menu} a[href='/users/log-out'][data-method=delete]")
        assert has_element?(view, "#{menu} button[data-phx-theme=dark]")
      end

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#sidebar a[aria-current=page][href='/users/settings']")
    end
  end

  describe "without a household" do
    setup :register_and_log_in_user

    test "the account menu but no sections", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/welcome")

      assert has_element?(view, "#account-dropdown", user.email)
      refute has_element?(view, "#tab-bar")
      refute has_element?(view, "#sidebar")
    end
  end

  test "signed out: the logo and theme toggle only", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, "#top-bar button[data-phx-theme=light]")
    refute has_element?(view, "#account-dropdown")
    refute has_element?(view, "#tab-bar")
  end
end
