defmodule Mealplan.Repo do
  use Ecto.Repo,
    otp_app: :mealplan,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Production Repo config from environment variables, called from
  `config/runtime.exs`.

  Either `DATABASE_URL` (`ecto://USER:PASS@HOST:PORT/DATABASE`) or discrete
  variables, which avoid URL-escaping the password and let compose share it
  with the Postgres container:

    * `DATABASE_HOST` (default `db`), `DATABASE_PORT` (default `5432`)
    * `DATABASE_NAME` (default `mealplan`), `DATABASE_USER` (default `mealplan`)
    * `DATABASE_PASSWORD`, or `DATABASE_PASSWORD_FILE` naming a file that holds it
      (a compose secret shared with the Postgres container); one is required

  `POOL_SIZE` defaults to 10; `ECTO_IPV6=true` connects over IPv6.
  """
  def config_from_env(env \\ System.get_env()) do
    connection =
      case present(env, "DATABASE_URL") do
        nil -> discrete_connection(env)
        url -> [url: url]
      end

    connection ++
      [
        pool_size: String.to_integer(env_or(env, "POOL_SIZE", "10")),
        socket_options: if(env["ECTO_IPV6"] in ~w(true 1), do: [:inet6], else: [])
      ]
  end

  defp discrete_connection(env) do
    [
      hostname: env_or(env, "DATABASE_HOST", "db"),
      port: String.to_integer(env_or(env, "DATABASE_PORT", "5432")),
      database: env_or(env, "DATABASE_NAME", "mealplan"),
      username: env_or(env, "DATABASE_USER", "mealplan"),
      password: password(env)
    ]
  end

  defp password(env) do
    cond do
      password = present(env, "DATABASE_PASSWORD") ->
        password

      path = present(env, "DATABASE_PASSWORD_FILE") ->
        # Trailing newlines only, as the Postgres entrypoint does with $(< file).
        path |> File.read!() |> String.replace(~r/\n+\z/, "")

      true ->
        raise "environment variable DATABASE_PASSWORD, DATABASE_PASSWORD_FILE or DATABASE_URL is missing"
    end
  end

  defp env_or(env, name, default), do: present(env, name) || default

  defp present(env, name) do
    case env[name] do
      "" -> nil
      value -> value
    end
  end
end
