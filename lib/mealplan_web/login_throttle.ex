defmodule MealplanWeb.LoginThrottle do
  @moduledoc """
  Rate limits for unauthenticated login actions, keyed by both client IP and
  email so neither a single client nor a distributed attack against one
  account can brute-force passwords or flood an inbox with magic links.
  """
  alias Mealplan.RateLimit

  @minute to_timeout(minute: 1)
  @quarter_hour to_timeout(minute: 15)

  @doc "Requesting a magic link email: 5/min per IP, 3 per 15 min per email."
  @spec magic_link(:inet.ip_address() | nil, String.t()) :: :ok | {:error, :rate_limited}
  def magic_link(ip, email) do
    check([
      {"magic_link:ip:#{format_ip(ip)}", @minute, 5},
      {"magic_link:email:#{normalize(email)}", @quarter_hour, 3}
    ])
  end

  @doc "Password login attempts: 10/min per IP, 10 per 15 min per email."
  @spec password_login(:inet.ip_address() | nil, String.t()) :: :ok | {:error, :rate_limited}
  def password_login(ip, email) do
    check([
      {"password_login:ip:#{format_ip(ip)}", @minute, 10},
      {"password_login:email:#{normalize(email)}", @quarter_hour, 10}
    ])
  end

  @doc "The message shown when a limit is hit."
  def message, do: "Too many attempts. Please wait a few minutes and try again."

  # Every bucket is hit (not short-circuited) so an attacker rotating emails
  # still consumes the per-IP budget.
  defp check(buckets) do
    results = Enum.map(buckets, fn {key, scale, limit} -> RateLimit.hit(key, scale, limit) end)

    if Enum.all?(results, &match?({:allow, _}, &1)), do: :ok, else: {:error, :rate_limited}
  end

  defp format_ip(nil), do: "unknown"
  defp format_ip(ip), do: ip |> :inet.ntoa() |> to_string()

  defp normalize(email), do: email |> to_string() |> String.trim() |> String.downcase()
end
