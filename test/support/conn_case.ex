defmodule MealplanWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MealplanWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use MealplanWeb, :verified_routes

      import MealplanWeb.ConnCase
      import Phoenix.ConnTest

      # Import conveniences for testing with connections
      import Plug.Conn

      # The default endpoint for testing
      @endpoint MealplanWeb.Endpoint
    end
  end

  setup tags do
    Mealplan.DataCase.setup_sandbox(tags)
    {:ok, conn: with_unique_client_ip(Phoenix.ConnTest.build_conn())}
  end

  @doc """
  Gives the connection a unique client IP so per-IP rate limits (which live
  in a shared ETS table) don't leak between tests.
  """
  def with_unique_client_ip(conn) do
    n = System.unique_integer([:positive])
    ip = {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}

    Plug.Test.put_peer_data(%{conn | remote_ip: ip}, %{address: ip, port: 40_000, ssl_cert: nil})
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = Mealplan.AccountsFixtures.user_fixture()
    scope = Mealplan.Accounts.Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.to_list()

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = Mealplan.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    Mealplan.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
