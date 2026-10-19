defmodule MealplanWeb.RedactTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias MealplanWeb.Redact

  doctest Redact

  describe "path/1" do
    test "redacts magic-link and email-confirmation tokens" do
      assert Redact.path("/users/log-in/SFMyNTY.abc-_") == "/users/log-in/[FILTERED]"

      assert Redact.path("/users/settings/confirm-email/abc?x=1") ==
               "/users/settings/confirm-email/[FILTERED]?x=1"
    end

    test "leaves other paths alone" do
      assert Redact.path("/users/log-in") == "/users/log-in"
      assert Redact.path("/users/settings") == "/users/settings"
    end
  end

  describe "request_log_level/1" do
    test "does not log requests whose path carries a token" do
      assert Redact.request_log_level(conn(:get, "/users/log-in/abc")) == false
    end

    test "logs other requests at info" do
      assert Redact.request_log_level(conn(:get, "/users/log-in")) == :info
      assert Redact.request_log_level(conn(:get, "/")) == :info
    end
  end

  describe "sanitize/1" do
    test "filters sensitive params and tokens in URLs and headers, keeping the rest" do
      context = %{
        "request.path" => "/users/log-in/secret-token",
        "request.params" => %{
          "user" => %{"email" => "a@b.c", "password" => "hunter2"},
          "_csrf_token" => "csrf",
          "token" => "secret-token"
        },
        "request.headers" => %{"referer" => "https://h/users/log-in/secret-token"},
        "live_view.event_params" => [%{"Password" => "hunter2"}],
        "count" => 3
      }

      sanitized = Redact.sanitize(context)

      refute inspect(sanitized) =~ "hunter2"
      refute inspect(sanitized) =~ "secret-token"
      refute inspect(sanitized) =~ "csrf\""
      assert sanitized["request.params"]["user"]["email"] == "a@b.c"
      assert sanitized["request.path"] == "/users/log-in/[FILTERED]"
      assert sanitized["count"] == 3
    end
  end
end
