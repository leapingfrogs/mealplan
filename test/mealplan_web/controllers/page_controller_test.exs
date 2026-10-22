defmodule MealplanWeb.PageControllerTest do
  use MealplanWeb.ConnCase, async: true

  test "GET / sends visitors to log in, without an error", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
    refute Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  test "GET / sends people who are logged in to the week plan", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    assert redirected_to(get(conn, ~p"/")) == ~p"/plan"
  end
end
