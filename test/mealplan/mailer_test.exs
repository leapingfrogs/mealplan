defmodule Mealplan.MailerTest do
  use ExUnit.Case, async: true

  alias Mealplan.Mailer

  @env %{
    "SMTP_HOST" => "smtp.example.com",
    "SMTP_USERNAME" => "mealplan@example.com",
    "SMTP_PASSWORD" => "secret",
    "SMTP_FROM" => "mealplan@example.com"
  }

  describe "smtp_config_from_env/1" do
    test "defaults to STARTTLS on port 587 with certificate verification" do
      config = Mailer.smtp_config_from_env(@env)

      assert config[:adapter] == Swoosh.Adapters.SMTP
      assert config[:relay] == "smtp.example.com"
      assert config[:port] == 587
      assert config[:username] == "mealplan@example.com"
      assert config[:password] == "secret"
      assert config[:auth] == :always
      assert config[:ssl] == false
      assert config[:tls] == :always
      assert config[:tls_options][:verify] == :verify_peer
      assert config[:tls_options][:server_name_indication] == ~c"smtp.example.com"
      assert [_ | _] = config[:tls_options][:cacerts]
    end

    test "uses implicit TLS with verification on port 465" do
      config = Mailer.smtp_config_from_env(Map.put(@env, "SMTP_PORT", "465"))

      assert config[:port] == 465
      assert config[:ssl] == true
      assert config[:tls] == :never
      assert config[:sockopts][:verify] == :verify_peer
    end

    for name <- ~w(SMTP_HOST SMTP_USERNAME SMTP_PASSWORD) do
      test "raises when #{name} is missing or blank" do
        assert_raise RuntimeError, ~r/#{unquote(name)} is missing/, fn ->
          Mailer.smtp_config_from_env(Map.delete(@env, unquote(name)))
        end

        assert_raise RuntimeError, ~r/#{unquote(name)} is missing/, fn ->
          Mailer.smtp_config_from_env(Map.put(@env, unquote(name), ""))
        end
      end
    end
  end

  describe "from_env/1" do
    test "uses SMTP_FROM with a default display name" do
      assert Mailer.from_env(@env) == {"Mealplan", "mealplan@example.com"}
    end

    test "uses SMTP_FROM_NAME when set" do
      assert Mailer.from_env(Map.put(@env, "SMTP_FROM_NAME", "Family Meals")) ==
               {"Family Meals", "mealplan@example.com"}
    end

    test "raises when SMTP_FROM is missing" do
      assert_raise RuntimeError, ~r/SMTP_FROM is missing/, fn ->
        Mailer.from_env(Map.delete(@env, "SMTP_FROM"))
      end
    end
  end

  test "from/0 returns the configured sender" do
    assert Mailer.from() == {"Mealplan", "mealplan@localhost"}
  end
end
