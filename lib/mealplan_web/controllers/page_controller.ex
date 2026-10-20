defmodule MealplanWeb.PageController do
  use MealplanWeb, :controller

  # The week plan is the home page. It sends visitors to log in, and users
  # without a household to /welcome.
  def home(conn, _params) do
    redirect(conn, to: ~p"/plan")
  end
end
