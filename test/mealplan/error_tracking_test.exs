defmodule Mealplan.ErrorTrackingTest do
  # Toggles the global :error_tracker, :enabled setting.
  use Mealplan.DataCase, async: false

  setup do
    Application.put_env(:error_tracker, :enabled, true)
    on_exit(fn -> Application.put_env(:error_tracker, :enabled, false) end)
  end

  test "reported errors are stored with credentials redacted" do
    {exception, stacktrace} =
      try do
        raise "boom"
      rescue
        e -> {e, __STACKTRACE__}
      end

    occurrence =
      ErrorTracker.report(exception, stacktrace, %{
        "request.path" => "/users/log-in/secret-token",
        "request.params" => %{"user" => %{"password" => "hunter2"}}
      })

    stored = Repo.get!(ErrorTracker.Occurrence, occurrence.id)

    assert stored.reason == "boom"
    assert stored.context["request.path"] == "/users/log-in/[FILTERED]"
    assert stored.context["request.params"]["user"]["password"] == "[FILTERED]"
  end
end
