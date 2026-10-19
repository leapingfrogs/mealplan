defmodule MealplanWeb.TrustedProxyTest do
  # Mutates the :trusted_proxies application env.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias MealplanWeb.TrustedProxy

  doctest TrustedProxy

  @npm {172, 20, 0, 5}
  @trusted TrustedProxy.parse_cidrs!("172.20.0.0/16")

  describe "parse_cidrs!/1" do
    test "parses IPv4 and IPv6 CIDRs and bare addresses" do
      assert TrustedProxy.parse_cidrs!("10.0.0.0/8,fd00::/8 , 192.168.1.1") == [
               {{10, 0, 0, 0}, 8},
               {{0xFD00, 0, 0, 0, 0, 0, 0, 0}, 8},
               {{192, 168, 1, 1}, 32}
             ]
    end

    test "treats nil and empty as no trusted proxies" do
      assert TrustedProxy.parse_cidrs!(nil) == []
      assert TrustedProxy.parse_cidrs!("") == []
    end

    test "rejects invalid addresses and prefixes" do
      assert_raise ArgumentError, ~r/address/, fn -> TrustedProxy.parse_cidrs!("nope/8") end
      assert_raise ArgumentError, ~r/prefix/, fn -> TrustedProxy.parse_cidrs!("10.0.0.0/33") end
      assert_raise ArgumentError, ~r/prefix/, fn -> TrustedProxy.parse_cidrs!("10.0.0.0/x") end
    end
  end

  describe "from_env!/2" do
    test "reads TRUSTED_PROXIES" do
      assert TrustedProxy.from_env!("TRUSTED_PROXIES", %{"TRUSTED_PROXIES" => "172.16.8.0/24"}) ==
               [{{172, 16, 8, 0}, 24}]

      assert TrustedProxy.from_env!("TRUSTED_PROXIES", %{}) == []
    end

    test "names the variable when the value is invalid" do
      assert_raise ArgumentError,
                   ~r/^TRUSTED_PROXIES in the environment is invalid: .*"=172.16.8.0\/24"/,
                   fn ->
                     TrustedProxy.from_env!("TRUSTED_PROXIES", %{
                       "TRUSTED_PROXIES" => "=172.16.8.0/24"
                     })
                   end
    end
  end

  describe "client_ip/3" do
    test "ignores X-Forwarded-For from an untrusted peer" do
      assert TrustedProxy.client_ip({203, 0, 113, 9}, ["1.2.3.4"], @trusted) == {203, 0, 113, 9}
    end

    test "uses the forwarded client from a trusted proxy" do
      assert TrustedProxy.client_ip(@npm, ["192.168.1.50"], @trusted) == {192, 168, 1, 50}
    end

    test "uses the rightmost entry, so a client cannot spoof its address" do
      assert TrustedProxy.client_ip(@npm, ["6.6.6.6, 192.168.1.50"], @trusted) ==
               {192, 168, 1, 50}

      assert TrustedProxy.client_ip(@npm, ["6.6.6.6", "192.168.1.50"], @trusted) ==
               {192, 168, 1, 50}
    end

    test "skips further trusted proxies in the chain" do
      assert TrustedProxy.client_ip(@npm, ["100.64.1.2, 172.20.0.9"], @trusted) ==
               {100, 64, 1, 2}
    end

    test "stops at an unparseable entry rather than trusting what precedes it" do
      assert TrustedProxy.client_ip(@npm, ["6.6.6.6, garbage"], @trusted) == @npm
    end

    test "falls back to the peer when there is no header" do
      assert TrustedProxy.client_ip(@npm, [], @trusted) == @npm
    end

    test "handles IPv4-mapped IPv6 peers from dual-stack listeners" do
      mapped = {0, 0, 0, 0, 0, 0xFFFF, 0xAC14, 0x0005}
      assert TrustedProxy.client_ip(mapped, ["192.168.1.50"], @trusted) == {192, 168, 1, 50}
    end

    test "trusts nothing by default" do
      assert TrustedProxy.client_ip(@npm, ["192.168.1.50"], []) == @npm
    end
  end

  describe "plug" do
    setup do
      previous = Application.get_env(:mealplan, :trusted_proxies)
      Application.put_env(:mealplan, :trusted_proxies, @trusted)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:mealplan, :trusted_proxies, previous),
          else: Application.delete_env(:mealplan, :trusted_proxies)
      end)
    end

    defp request(peer, headers) do
      conn = %{conn(:get, "/") | remote_ip: peer}

      headers
      |> Enum.reduce(conn, fn {k, v}, conn -> put_req_header(conn, k, v) end)
      |> TrustedProxy.call(TrustedProxy.init([]))
    end

    test "rewrites remote_ip and scheme for a trusted proxy" do
      conn =
        request(@npm, [{"x-forwarded-for", "192.168.1.50"}, {"x-forwarded-proto", "https"}])

      assert conn.remote_ip == {192, 168, 1, 50}
      assert conn.scheme == :https
      assert conn.port == 443
    end

    test "leaves untrusted requests untouched" do
      conn =
        request({203, 0, 113, 9}, [{"x-forwarded-for", "1.2.3.4"}, {"x-forwarded-proto", "https"}])

      assert conn.remote_ip == {203, 0, 113, 9}
      assert conn.scheme == :http
    end
  end
end
