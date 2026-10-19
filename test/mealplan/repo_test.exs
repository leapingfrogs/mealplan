defmodule Mealplan.RepoTest do
  use ExUnit.Case, async: true

  alias Mealplan.Repo

  describe "config_from_env/1" do
    test "uses DATABASE_URL when set" do
      config = Repo.config_from_env(%{"DATABASE_URL" => "ecto://u:p@h/d", "DATABASE_HOST" => "x"})

      assert config[:url] == "ecto://u:p@h/d"
      refute config[:hostname]
      assert config[:pool_size] == 10
      assert config[:socket_options] == []
    end

    test "falls back to discrete variables with compose-friendly defaults" do
      config = Repo.config_from_env(%{"DATABASE_URL" => "", "DATABASE_PASSWORD" => "p@ss/w:rd"})

      assert config[:hostname] == "db"
      assert config[:port] == 5432
      assert config[:database] == "mealplan"
      assert config[:username] == "mealplan"
      assert config[:password] == "p@ss/w:rd"
      refute config[:url]
    end

    test "honours discrete overrides, POOL_SIZE and ECTO_IPV6" do
      config =
        Repo.config_from_env(%{
          "DATABASE_HOST" => "pg",
          "DATABASE_PORT" => "6543",
          "DATABASE_NAME" => "n",
          "DATABASE_USER" => "u",
          "DATABASE_PASSWORD" => "p",
          "POOL_SIZE" => "3",
          "ECTO_IPV6" => "true"
        })

      assert config[:hostname] == "pg"
      assert config[:port] == 6543
      assert config[:database] == "n"
      assert config[:username] == "u"
      assert config[:pool_size] == 3
      assert config[:socket_options] == [:inet6]
    end

    test "requires a password without DATABASE_URL" do
      assert_raise RuntimeError, ~r/DATABASE_PASSWORD/, fn -> Repo.config_from_env(%{}) end
    end
  end
end
