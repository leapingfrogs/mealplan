defmodule MealplanWeb.PageController do
  use MealplanWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
