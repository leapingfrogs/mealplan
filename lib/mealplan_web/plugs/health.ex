defmodule MealplanWeb.Plugs.Health do
  @moduledoc """
  Health endpoints for the container healthcheck and reverse proxy.

    * `GET /health/live` - the VM is up and serving requests. Never touches
      the database, so a database outage doesn't restart the container.
    * `GET /health/ready` - the app can reach the database; 503 otherwise.

  Mounted in the endpoint before request logging, telemetry and sessions, so
  probes are cheap and don't flood the logs. Responses deliberately reveal
  nothing beyond the status.
  """
  @behaviour Plug

  import Plug.Conn

  require Logger

  @impl Plug
  def init(opts), do: Keyword.put_new(opts, :repo, Mealplan.Repo)

  @impl Plug
  def call(%Plug.Conn{method: method, path_info: ["health", check]} = conn, opts)
      when method in ["GET", "HEAD"] and check in ["live", "ready"] do
    {status, body} =
      case check do
        "live" -> {200, "ok"}
        "ready" -> if database_ready?(opts[:repo]), do: {200, "ok"}, else: {503, "unavailable"}
      end

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp database_ready?(repo) do
    match?({:ok, _}, repo.query("SELECT 1", [], timeout: 1_000, log: false))
  rescue
    error ->
      Logger.warning("Readiness check failed: #{Exception.message(error)}")
      false
  end
end
