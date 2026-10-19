defmodule MealplanWeb.SecurityHeadersTest do
  use MealplanWeb.ConnCase, async: true

  test "browser responses carry a strict CSP whose nonce matches the inline script", %{
    conn: conn
  } do
    conn = get(conn, ~p"/users/log-in")
    [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "default-src 'self'"
    assert csp =~ "style-src 'self' 'nonce-"
    assert csp =~ "object-src 'none'"
    assert csp =~ "frame-ancestors 'none'"
    refute csp =~ "unsafe-inline"
    refute csp =~ "unsafe-eval"

    [_, nonce] = Regex.run(~r/script-src 'self' 'nonce-([^']+)'/, csp)
    assert html_response(conn, 200) =~ ~s(<script nonce="#{nonce}">)
  end

  test "the nonce changes on every request", %{conn: conn} do
    nonce = fn ->
      [csp] = conn |> get(~p"/users/log-in") |> get_resp_header("content-security-policy")
      csp
    end

    refute nonce.() == nonce.()
  end

  test "hardening headers are set", %{conn: conn} do
    conn = get(conn, ~p"/users/log-in")

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert get_resp_header(conn, "cross-origin-opener-policy") == ["same-origin"]
    assert [permissions] = get_resp_header(conn, "permissions-policy")
    assert permissions =~ "camera=()"
  end

  test "the session cookie is http-only, same-site and secure over https", %{conn: conn} do
    conn = get(conn, "https://www.example.com/users/log-in")
    [cookie] = for c <- get_resp_header(conn, "set-cookie"), c =~ "_mealplan_key=", do: c
    attributes = cookie |> String.downcase() |> String.split("; ")

    assert "httponly" in attributes
    assert "samesite=lax" in attributes
    assert "secure" in attributes
  end
end
