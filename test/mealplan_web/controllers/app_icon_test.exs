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

    assert LazyHTML.attribute(LazyHTML.query(document, "link[rel=manifest]"), "href") ==
             ["/manifest.webmanifest"]

    for path <- ["/apple-touch-icon.png", "/favicon.ico", "/images/icon.svg"] do
      assert build_conn() |> get(path) |> response(200), path
    end
  end

  test "the web app manifest opens the app standalone from its own icons", %{conn: conn} do
    conn = get(conn, ~p"/manifest.webmanifest")
    assert ["application/manifest+json" <> _] = get_resp_header(conn, "content-type")

    manifest = conn |> response(200) |> JSON.decode!()
    assert %{"display" => "standalone", "scope" => "/", "start_url" => "/"} = manifest

    for %{"src" => src} <- manifest["icons"] do
      assert build_conn() |> get(src) |> response(200), src
    end
  end
end
