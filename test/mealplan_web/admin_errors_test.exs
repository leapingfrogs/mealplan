defmodule MealplanWeb.AdminErrorsTest do
  use MealplanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mealplan.AccountsFixtures

  alias Mealplan.Accounts
  alias Mealplan.Accounts.User
  alias MealplanWeb.UserAuth
  alias Phoenix.LiveView

  defp admin_fixture do
    {:ok, admin} = Accounts.set_admin(user_fixture(), true)
    admin
  end

  describe "GET /admin/errors" do
    test "redirects anonymous visitors to log in", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/admin/errors")) == ~p"/users/log-in"
    end

    test "is a 404 for logged-in non-admins", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/admin/errors")

      assert html_response(conn, 404)
      refute conn.resp_body =~ "ErrorTracker"
    end

    test "hides error detail pages from non-admins too", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get("/admin/errors/#{Ecto.UUID.generate()}")

      assert html_response(conn, 404)
    end

    test "shows the dashboard to admins under our CSP", %{conn: conn} do
      conn = conn |> log_in_user(admin_fixture()) |> get(~p"/admin/errors")
      html = html_response(conn, 200)
      [csp] = get_resp_header(conn, "content-security-policy")
      [_, nonce] = Regex.run(~r/script-src 'self' 'nonce-([^']+)'/, csp)

      assert html =~ ~s(<style nonce="#{nonce}">)
      assert html =~ ~s(<script nonce="#{nonce}">)
    end

    test "the dashboard LiveView connects for admins", %{conn: conn} do
      assert {:ok, _view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin/errors")
    end
  end

  describe "on_mount :require_admin" do
    defp socket,
      do: %LiveView.Socket{endpoint: MealplanWeb.Endpoint, assigns: %{__changed__: %{}}}

    defp session_for(conn, user) do
      conn
      |> init_test_session(%{})
      |> put_session(:user_token, Accounts.generate_user_session_token(user))
      |> get_session()
    end

    test "continues for admins", %{conn: conn} do
      admin = admin_fixture()

      assert {:cont, socket} =
               UserAuth.on_mount(:require_admin, %{}, session_for(conn, admin), socket())

      assert socket.assigns.current_scope.user.id == admin.id
    end

    test "halts for non-admins", %{conn: conn} do
      session = session_for(conn, user_fixture())
      assert {:halt, _socket} = UserAuth.on_mount(:require_admin, %{}, session, socket())
    end

    test "halts without a session", %{conn: conn} do
      session = conn |> init_test_session(%{}) |> get_session()
      assert {:halt, _socket} = UserAuth.on_mount(:require_admin, %{}, session, socket())
    end
  end

  test "admin cannot be set through the email changeset" do
    changeset = User.email_changeset(%User{}, %{email: unique_user_email(), admin: true})

    refute Ecto.Changeset.get_field(changeset, :admin)
  end
end
