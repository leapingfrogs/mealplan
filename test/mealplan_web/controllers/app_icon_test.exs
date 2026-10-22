defmodule MealplanWeb.AppIconTest do
  use MealplanWeb.ConnCase, async: true

  test "pages link the favicon and home screen icon, and both are served", %{conn: conn} do
    html = conn |> get(~p"/users/log-in") |> html_response(200)
    document = LazyHTML.from_document(html)

    assert LazyHTML.attribute(LazyHTML.query(document, "link[rel=apple-touch-icon]"), "href") ==
             ["/apple-touch-icon.png"]

    assert LazyHTML.attribute(LazyHTML.query(document, "link[rel=icon]"), "href") ==
             ["/favicon.ico", "/images/icon.svg"]

    assert LazyHTML.attribute(LazyHTML.query(document, "title"), "data-suffix") == [" · Mealplan"]

    for path <- ["/apple-touch-icon.png", "/favicon.ico", "/images/icon.svg"] do
      assert build_conn() |> get(path) |> response(200), path
    end
  end
end
