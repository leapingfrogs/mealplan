defmodule Mix.Tasks.Mealplan.InviteTest do
  use Mealplan.DataCase

  import Mealplan.AccountsFixtures

  alias Mealplan.Accounts
  alias Mix.Tasks.Mealplan.Invite

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "invites the given email" do
    email = unique_user_email()

    Invite.run([email])

    assert_received {:mix_shell, :info, ["Invited " <> ^email]}
    assert Accounts.get_user_by_email(email)
    assert_received {:email, %Swoosh.Email{to: [{"", ^email}]}}
  end

  test "raises when the email already has an account" do
    %{email: email} = user_fixture()

    assert_raise Mix.Error, ~r/has already been taken/, fn -> Invite.run([email]) end
  end

  test "raises usage without exactly one email" do
    assert_raise Mix.Error, ~r/Usage/, fn -> Invite.run([]) end
  end
end
