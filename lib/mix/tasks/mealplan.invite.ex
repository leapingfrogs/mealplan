defmodule Mix.Tasks.Mealplan.Invite do
  @shortdoc "Invites a user by email (registration is invite-only)"

  @moduledoc """
  Creates an account for the given email and sends it a magic login link.

      $ mix mealplan.invite person@example.com

  In development the email appears at /dev/mailbox.
  """
  use Mix.Task
  use MealplanWeb, :verified_routes

  alias Mealplan.Accounts

  @requirements ["app.start"]

  @impl Mix.Task
  def run([email]) do
    case Accounts.invite_user(email, &url(~p"/users/log-in/#{&1}")) do
      {:ok, user} ->
        Mix.shell().info("Invited #{user.email}")

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)

        Mix.raise("Could not invite #{email}: #{inspect(errors)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix mealplan.invite EMAIL")
end
