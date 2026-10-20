defmodule Mealplan.Accounts.UserNotifier do
  @moduledoc false
  import Swoosh.Email

  alias Mealplan.Accounts.User
  alias Mealplan.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Mailer.from())
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  @doc """
  Deliver an invitation to join a household, with a magic login link.
  """
  def deliver_household_invitation(user, url, details) do
    %{
      household_name: household,
      inviter_email: inviter,
      expires_at: expires_at,
      login_url: login_url
    } = details

    deliver(user.email, "#{inviter} invited you to #{household} on Mealplan", """

    ==============================

    Hi #{user.email},

    #{inviter} has invited you to join "#{household}" on Mealplan, to plan
    meals and share recipes together.

    Log in with this link to join:

    #{url}

    #{link_validity(details, login_url, Calendar.strftime(expires_at, "%-d %B %Y"))}

    If you weren't expecting this, you can ignore this email.

    ==============================
    """)
  end

  defp link_validity(%{link_lasts_until_expiry: true}, _login_url, until) do
    "The link and the invitation are valid until #{until}."
  end

  defp link_validity(_details, login_url, until) do
    """
    The link works for 15 minutes. After that, go to #{login_url}
    and log in with this email address. The invitation itself is valid until
    #{until}.\
    """
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
