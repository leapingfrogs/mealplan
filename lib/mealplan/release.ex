defmodule Mealplan.Release do
  @moduledoc """
  Tasks for production, where Mix is not available. Run them with
  `bin/mealplan eval` inside the container, e.g.

      bin/mealplan eval 'Mealplan.Release.invite_user("me@example.com", admin: true)'
      bin/mealplan eval 'Mealplan.Release.set_admin("me@example.com")'

  `bin/migrate` (run by `bin/server` on every start) calls `migrate/0`.
  """
  use MealplanWeb, :verified_routes

  alias Mealplan.Accounts

  @app :mealplan

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates an account and emails it a magic login link. Raises on failure.

  Options: `admin: true` to make the user an administrator.
  """
  def invite_user(email, opts \\ []) do
    start_app()

    case Accounts.invite_user(email, &url(~p"/users/log-in/#{&1}"), opts) do
      {:ok, user} ->
        IO.puts("Invited #{user.email}#{if user.admin, do: " (admin)"}")
        {:ok, user}

      {:error, %Ecto.Changeset{} = changeset} ->
        raise "Could not invite #{email}: #{error_messages(changeset)}"

      {:error, reason} ->
        raise "Created #{email} but could not send the invitation email (#{inspect(reason)}). " <>
                "Once email works they can request a link from the log-in page."
    end
  end

  @doc "Grants (or with `false`, revokes) admin rights for an existing user. Raises on failure."
  def set_admin(email, admin? \\ true) when is_boolean(admin?) do
    start_app()

    user = Accounts.get_user_by_email(email) || raise "No user with email #{email}"
    {:ok, user} = Accounts.set_admin(user, admin?)
    IO.puts("#{user.email} is #{if user.admin, do: "now", else: "no longer"} an admin")
    {:ok, user}
  end

  @doc "Formats changeset errors as `field: message, ...`."
  def error_messages(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  # The Repo, Mailer and Endpoint (for URLs) are needed. Under `eval` the app
  # is not running yet; the endpoint only listens when PHX_SERVER is set.
  defp start_app do
    {:ok, _} = Application.ensure_all_started(@app)
    :ok
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    {:ok, _} = Application.ensure_all_started(:ssl)
    :ok = Application.ensure_loaded(@app)
  end
end
