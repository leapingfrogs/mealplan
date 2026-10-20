defmodule MealplanWeb.PageControllerTest do
  use MealplanWeb.ConnCase, async: true

  test "GET / sends people to the week plan", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == ~p"/plan"
  end
end
