defmodule MealplanWeb.PageController do
  use MealplanWeb, :controller

  # The week plan is the home page for anyone logged in (it sends users
  # without a household to /welcome). Visitors go straight to the login
  # page, which welcomes them, without the "You must log in" error.
  def home(%{assigns: %{current_scope: %{user: %{}}}} = conn, _params),
    do: redirect(conn, to: ~p"/plan")

  def home(conn, _params), do: redirect(conn, to: ~p"/users/log-in")
end
