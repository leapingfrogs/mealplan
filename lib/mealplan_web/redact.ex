defmodule MealplanWeb.Redact do
  @moduledoc """
  Keeps credentials out of request logs and error reports.

  Magic-link and email-confirmation tokens travel in the URL path
  (`/users/log-in/:token`, `/users/settings/confirm-email/:token`), where
  `:filter_parameters` cannot reach them, and are valid until used. Params
  whose key matches `:filter_parameters` (password, token) are filtered too.
  """
  @behaviour ErrorTracker.Filter

  @filtered "[FILTERED]"
  # Mirrors :phoenix, :filter_parameters (which Phoenix compiles in place at boot).
  @sensitive_keys ~w(password token)
  @token_path ~r{(/users/(?:log-in|settings/confirm-email))/[^/?#\s"]+}

  @doc """
  Replaces tokens in any URL or path within `string`.

      iex> MealplanWeb.Redact.path("https://h/users/log-in/abc123?x=1")
      "https://h/users/log-in/[FILTERED]?x=1"
  """
  @spec path(String.t()) :: String.t()
  def path(string), do: Regex.replace(@token_path, string, "\\1/#{@filtered}")

  @doc """
  Plug.Telemetry `:log` callback: the request is logged at `:info` unless its
  path carries a token, in which case it is not logged at all.
  """
  @spec request_log_level(Plug.Conn.t()) :: :info | false
  def request_log_level(conn) do
    if Regex.match?(@token_path, conn.request_path), do: false, else: :info
  end

  @doc "ErrorTracker filter: redacts sensitive params and tokens in URLs."
  @impl ErrorTracker.Filter
  def sanitize(context), do: values(context, @sensitive_keys)

  defp values(%{__struct__: _} = struct, _keys), do: struct

  defp values(%{} = map, keys) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key, keys), do: {key, @filtered}, else: {key, values(value, keys)}
    end)
  end

  defp values(list, keys) when is_list(list), do: Enum.map(list, &values(&1, keys))
  defp values(string, _keys) when is_binary(string), do: path(string)
  defp values(other, _keys), do: other

  defp sensitive_key?(key, keys) when is_binary(key) or is_atom(key) do
    key = key |> to_string() |> String.downcase()
    Enum.any?(keys, &String.contains?(key, &1))
  end

  defp sensitive_key?(_key, _keys), do: false
end
