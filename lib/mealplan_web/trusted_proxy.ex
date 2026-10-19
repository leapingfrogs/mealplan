defmodule MealplanWeb.TrustedProxy do
  @moduledoc """
  Resolves the real client IP and scheme behind the reverse proxy.

  `X-Forwarded-For` and `X-Forwarded-Proto` are only honoured when the TCP
  peer is inside one of the configured trusted proxy CIDRs (the Docker network
  shared with Nginx Proxy Manager). Anything else could spoof them.

  The client is the rightmost `X-Forwarded-For` entry that is not itself a
  trusted proxy: proxies append the address they received from, so entries
  further left are client-supplied and untrustworthy.

  Configure with `config :mealplan, :trusted_proxies, parse_cidrs!("...")`;
  it defaults to none, in which case headers are ignored.

  Used as a plug in the endpoint, and via `client_ip_from_socket/1` in
  LiveViews (websockets bypass the endpoint plug pipeline).
  """
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2]

  @typedoc "A parsed CIDR: network address and prefix length."
  @type cidr :: {:inet.ip_address(), non_neg_integer()}

  @doc """
  Parses a comma-separated list of CIDRs (or bare IPs) into `t:cidr/0`s.

      iex> MealplanWeb.TrustedProxy.parse_cidrs!("172.20.0.0/16, ::1")
      [{{172, 20, 0, 0}, 16}, {{0, 0, 0, 0, 0, 0, 0, 1}, 128}]
  """
  @spec parse_cidrs!(String.t() | nil) :: [cidr()]
  def parse_cidrs!(nil), do: []

  def parse_cidrs!(string) do
    string
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_cidr!/1)
  end

  defp parse_cidr!(cidr) do
    {address, prefix} =
      case String.split(cidr, "/", parts: 2) do
        [address, prefix] -> {address, prefix}
        [address] -> {address, nil}
      end

    ip =
      case :inet.parse_strict_address(String.to_charlist(address)) do
        {:ok, ip} -> ip
        {:error, _} -> raise ArgumentError, "invalid trusted proxy address: #{inspect(cidr)}"
      end

    bits = bit_size(ip_to_binary(ip))

    prefix =
      case prefix && Integer.parse(prefix) do
        nil -> bits
        {n, ""} when n in 0..bits//1 -> n
        _ -> raise ArgumentError, "invalid trusted proxy prefix: #{inspect(cidr)}"
      end

    {ip, prefix}
  end

  @doc """
  Returns the client IP given the TCP peer and `X-Forwarded-For` values.
  """
  @spec client_ip(:inet.ip_address(), [String.t()], [cidr()]) :: :inet.ip_address()
  def client_ip(peer, forwarded_for, trusted \\ trusted_proxies()) do
    peer = normalize(peer)

    if trusted?(peer, trusted) do
      forwarded_for
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&parse_ip/1)
      |> Enum.reverse()
      |> Enum.reduce_while(peer, fn
        nil, last -> {:halt, last}
        ip, _last -> if trusted?(ip, trusted), do: {:cont, ip}, else: {:halt, ip}
      end)
    else
      peer
    end
  end

  @doc """
  The client IP for a LiveView, from its `:peer_data` and `:x_headers`
  connect info. Returns `nil` when not connected.
  """
  @spec client_ip_from_socket(Phoenix.LiveView.Socket.t()) :: :inet.ip_address() | nil
  def client_ip_from_socket(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: peer} ->
        x_headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []
        client_ip(peer, for({"x-forwarded-for", value} <- x_headers, do: value))

      _ ->
        nil
    end
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    trusted = trusted_proxies()

    if trusted?(normalize(conn.remote_ip), trusted) do
      conn
      |> Map.put(
        :remote_ip,
        client_ip(conn.remote_ip, get_req_header(conn, "x-forwarded-for"), trusted)
      )
      |> put_scheme(get_req_header(conn, "x-forwarded-proto"))
    else
      conn
    end
  end

  defp put_scheme(%{scheme: :http} = conn, ["https"]), do: %{conn | scheme: :https, port: 443}
  defp put_scheme(conn, _), do: conn

  defp trusted_proxies, do: Application.get_env(:mealplan, :trusted_proxies) || []

  defp trusted?(ip, trusted), do: Enum.any?(trusted, &in_cidr?(ip, &1))

  defp in_cidr?(ip, {network, prefix}) do
    ip = ip_to_binary(ip)
    network = ip_to_binary(network)

    bit_size(ip) == bit_size(network) and prefix_bits(ip, prefix) == prefix_bits(network, prefix)
  end

  defp prefix_bits(binary, prefix) do
    <<bits::bitstring-size(^prefix), _::bitstring>> = binary
    bits
  end

  defp parse_ip(string) do
    case :inet.parse_strict_address(string |> String.trim() |> String.to_charlist()) do
      {:ok, ip} -> normalize(ip)
      {:error, _} -> nil
    end
  end

  # Dual-stack listeners report IPv4 peers as IPv4-mapped IPv6 addresses.
  defp normalize({0, 0, 0, 0, 0, 0xFFFF, ab, cd}),
    do: {div(ab, 256), rem(ab, 256), div(cd, 256), rem(cd, 256)}

  defp normalize(ip), do: ip

  defp ip_to_binary({a, b, c, d}), do: <<a, b, c, d>>

  defp ip_to_binary({a, b, c, d, e, f, g, h}),
    do: <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>
end
