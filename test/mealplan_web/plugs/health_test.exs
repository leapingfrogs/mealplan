defmodule MealplanWeb.Plugs.HealthTest do
  use MealplanWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  alias MealplanWeb.Plugs.Health

  defmodule DownRepo do
    def query(_sql, _params, _opts), do: raise(DBConnection.ConnectionError, "connection refused")
  end

  defmodule ErrorRepo do
    def query(_sql, _params, _opts), do: {:error, :timeout}
  end

  describe "through the endpoint" do
    test "GET /health/live returns 200 without a session cookie", %{conn: conn} do
      conn = get(conn, "/health/live")

      assert text_response(conn, 200) == "ok"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert conn.resp_cookies == %{}
    end

    test "GET /health/ready returns 200 when the database is reachable", %{conn: conn} do
      assert conn |> get("/health/ready") |> text_response(200) == "ok"
    end

    test "HEAD is supported", %{conn: conn} do
      assert conn |> head("/health/live") |> response(200)
    end

    test "other methods and paths fall through to the router", %{conn: conn} do
      assert conn |> post("/health/live") |> response(404)
      assert conn |> get("/health/other") |> response(404)
    end
  end

  describe "readiness when the database is unavailable" do
    test "returns 503 when the query raises", %{conn: conn} do
      log =
        capture_log(fn ->
          conn =
            Health.call(%{conn | path_info: ["health", "ready"]}, Health.init(repo: DownRepo))

          assert text_response(conn, 503) == "unavailable"
          assert conn.halted
        end)

      assert log =~ "Readiness check failed: connection refused"
    end

    test "returns 503 when the query errors", %{conn: conn} do
      conn = Health.call(%{conn | path_info: ["health", "ready"]}, Health.init(repo: ErrorRepo))
      assert text_response(conn, 503) == "unavailable"
    end

    test "liveness never touches the database", %{conn: conn} do
      conn = Health.call(%{conn | path_info: ["health", "live"]}, Health.init(repo: DownRepo))
      assert text_response(conn, 200) == "ok"
    end
  end
end
