defmodule MealplanWeb.LoginThrottleTest do
  use MealplanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mealplan.AccountsFixtures

  alias MealplanWeb.LoginThrottle

  defp unique_ip do
    n = System.unique_integer([:positive])
    {10, 200, rem(div(n, 256), 256), rem(n, 256)}
  end

  describe "magic_link/2" do
    test "allows 3 requests per email, then limits" do
      email = unique_user_email()

      for _ <- 1..3, do: assert(LoginThrottle.magic_link(unique_ip(), email) == :ok)
      assert LoginThrottle.magic_link(unique_ip(), email) == {:error, :rate_limited}
    end

    test "normalizes the email so case and whitespace don't bypass the limit" do
      email = unique_user_email()

      for variant <- [email, String.upcase(email), " #{email} "],
          do: assert(LoginThrottle.magic_link(unique_ip(), variant) == :ok)

      assert LoginThrottle.magic_link(unique_ip(), email) == {:error, :rate_limited}
    end

    test "allows 5 requests per IP across different emails, then limits" do
      ip = unique_ip()

      for _ <- 1..5, do: assert(LoginThrottle.magic_link(ip, unique_user_email()) == :ok)
      assert LoginThrottle.magic_link(ip, unique_user_email()) == {:error, :rate_limited}
    end
  end

  describe "password_login/2" do
    test "allows 10 attempts per IP, then limits" do
      ip = unique_ip()

      for _ <- 1..10, do: assert(LoginThrottle.password_login(ip, unique_user_email()) == :ok)
      assert LoginThrottle.password_login(ip, unique_user_email()) == {:error, :rate_limited}
    end

    test "allows 10 attempts per email across IPs, then limits" do
      email = unique_user_email()

      for _ <- 1..10, do: assert(LoginThrottle.password_login(unique_ip(), email) == :ok)
      assert LoginThrottle.password_login(unique_ip(), email) == {:error, :rate_limited}
    end
  end

  describe "login page" do
    test "stops sending magic links once the limit is hit", %{conn: conn} do
      user = user_fixture()
      assert_received {:email, _confirmation}

      submit = fn ->
        {:ok, lv, _html} = live(conn, ~p"/users/log-in")
        lv |> form("#login_form_magic", user: %{email: user.email}) |> render_submit()
      end

      for _ <- 1..3 do
        assert {:error, {:live_redirect, _}} = submit.()
        assert_received {:email, %{subject: "Log in instructions"}}
      end

      html = submit.()

      assert html =~ "Too many attempts"
      refute_received {:email, _}
    end

    test "rejects even a correct password once the limit is hit", %{conn: conn} do
      user = user_fixture() |> set_password()

      for _ <- 1..10 do
        conn
        |> post(~p"/users/log-in", %{"user" => %{"email" => user.email, "password" => "wrong"}})
        |> redirected_to()
      end

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      refute get_session(conn, :user_token)
    end
  end
end
