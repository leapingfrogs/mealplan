defmodule Mealplan.Mailer do
  use Swoosh.Mailer, otp_app: :mealplan

  @doc """
  The `{name, address}` that application emails are sent from.
  """
  def from, do: Application.fetch_env!(:mealplan, :mail_from)

  @doc """
  Builds the sender from `SMTP_FROM` (required) and `SMTP_FROM_NAME`.

  Called from `config/runtime.exs` in production.
  """
  def from_env(env \\ System.get_env()) do
    {Map.get(env, "SMTP_FROM_NAME", "Mealplan"), fetch_env!(env, "SMTP_FROM")}
  end

  @doc """
  Builds the Swoosh SMTP adapter configuration from environment variables.

  Called from `config/runtime.exs` in production. Requires `SMTP_HOST`,
  `SMTP_USERNAME` and `SMTP_PASSWORD`; `SMTP_PORT` defaults to 587.

  TLS is always required and the server certificate is verified against the
  OS trust store: port 465 uses implicit TLS, any other port uses STARTTLS.
  """
  def smtp_config_from_env(env \\ System.get_env()) do
    host = fetch_env!(env, "SMTP_HOST")
    port = env |> Map.get("SMTP_PORT", "587") |> String.to_integer()

    tls_options = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      depth: 99,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    encryption =
      if port == 465,
        do: [ssl: true, tls: :never, sockopts: tls_options],
        else: [ssl: false, tls: :always, tls_options: tls_options]

    [
      adapter: Swoosh.Adapters.SMTP,
      relay: host,
      port: port,
      username: fetch_env!(env, "SMTP_USERNAME"),
      password: fetch_env!(env, "SMTP_PASSWORD"),
      auth: :always,
      no_mx_lookups: true,
      retries: 2
    ] ++ encryption
  end

  defp fetch_env!(env, name) do
    case Map.get(env, name) do
      value when value in [nil, ""] -> raise "environment variable #{name} is missing"
      value -> value
    end
  end
end
