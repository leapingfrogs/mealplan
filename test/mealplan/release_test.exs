defmodule Mealplan.ReleaseTest do
  use Mealplan.DataCase, async: true

  import ExUnit.CaptureIO
  import Mealplan.AccountsFixtures

  alias Mealplan.Accounts
  alias Mealplan.Release

  describe "invite_user/2" do
    test "creates the user and emails a magic link to the endpoint URL" do
      email = unique_user_email()

      assert capture_io(fn -> assert {:ok, _} = Release.invite_user(email) end) =~
               "Invited #{email}"

      refute Accounts.get_user_by_email(email).admin
      assert_received {:email, %Swoosh.Email{to: [{"", ^email}], text_body: body}}
      assert body =~ MealplanWeb.Endpoint.url() <> "/users/log-in/"
    end

    test "can invite an admin" do
      email = unique_user_email()

      assert capture_io(fn -> Release.invite_user(email, admin: true) end) =~ "(admin)"
      assert Accounts.get_user_by_email(email).admin
    end

    test "raises a readable error when the email is taken" do
      %{email: email} = user_fixture()

      assert_raise RuntimeError, ~r/email has already been taken/, fn ->
        Release.invite_user(email)
      end
    end
  end

  describe "set_admin/2" do
    test "grants and revokes admin rights" do
      %{email: email} = user_fixture()

      assert capture_io(fn -> Release.set_admin(email) end) =~ "now an admin"
      assert Accounts.get_user_by_email(email).admin

      assert capture_io(fn -> Release.set_admin(email, false) end) =~ "no longer an admin"
      refute Accounts.get_user_by_email(email).admin
    end

    test "raises for an unknown email" do
      assert_raise RuntimeError, ~r/No user/, fn -> Release.set_admin("nobody@example.com") end
    end
  end
end
