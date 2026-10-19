defmodule Mix.Tasks.Mealplan.Invite do
  @shortdoc "Invites a user by email (registration is invite-only)"

  @moduledoc """
  Creates an account for the given email and sends it a magic login link.

      $ mix mealplan.invite person@example.com
      $ mix mealplan.invite --admin person@example.com

  `--admin` grants access to admin pages such as the error dashboard.

  In development the email appears at /dev/mailbox. In production use
  `Mealplan.Release.invite_user/2` instead.
  """
  use Mix.Task
  use MealplanWeb, :verified_routes

  alias Mealplan.Accounts
  alias Mealplan.Release

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: [admin: :boolean]) do
      {opts, [email], []} -> invite(email, opts)
      _ -> Mix.raise("Usage: mix mealplan.invite [--admin] EMAIL")
    end
  end

  defp invite(email, opts) do
    case Accounts.invite_user(email, &url(~p"/users/log-in/#{&1}"), opts) do
      {:ok, user} ->
        Mix.shell().info("Invited #{user.email}#{if user.admin, do: " (admin)"}")

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise("Could not invite #{email}: #{Release.error_messages(changeset)}")

      {:error, reason} ->
        Mix.raise("Created #{email} but could not send the invitation email: #{inspect(reason)}")
    end
  end
end
