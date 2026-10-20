defmodule MealplanWeb.HouseholdLive.InvitationsTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.AccountsFixtures
  import Mealplan.HouseholdsFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Accounts
  alias Mealplan.Accounts.Scope
  alias Mealplan.Households
  alias Mealplan.Repo

  defp invite(scope, email, url_fun \\ &"https://x/#{&1}") do
    {:ok, invitation} = Households.invite(scope, %{email: email}, url_fun, "https://x")
    invitation
  end

  describe "owner on /household" do
    setup :register_and_log_in_user_with_household

    test "invites someone and can revoke the invitation", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/household")

      html =
        view
        |> form("#invite-form", invitation: %{email: "guest@example.com"})
        |> render_submit()

      assert html =~ "Invitation sent to guest@example.com."
      assert has_element?(view, "#pending-invitations", "guest@example.com")
      assert has_element?(view, "#pending-invitations", "expires in 6 days")

      [invitation] = Households.list_pending_invitations(scope)

      view |> element("#invitation-#{invitation.id} button", "Revoke") |> render_click()

      refute has_element?(view, "#pending-invitations")
    end

    test "shows invitation errors", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/household")

      assert view |> form("#invite-form", invitation: %{email: "nope"}) |> render_change() =~
               "must have the @ sign"

      assert view |> form("#invite-form", invitation: %{email: user.email}) |> render_submit() =~
               "is already a member"
    end

    test "sees someone join live", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/household")
      invitee = user_fixture()
      invitation = invite(scope, invitee.email)
      assert has_element?(view, "#invitation-#{invitation.id}")

      {:ok, _} = Households.accept_invitation(Scope.for_user(invitee), invitation.id)

      assert has_element?(view, "#member-#{invitee.id}")
      refute has_element?(view, "#invitation-#{invitation.id}")
    end
  end

  describe "member on /household" do
    test "can't invite but can decline invitations to other households", %{conn: conn} do
      %{household: household} = household_fixture()
      %{user: member} = member_fixture(household)
      %{scope: other_owner} = household_fixture(user_fixture(), %{name: "Elsewhere"})
      invitation = invite(other_owner, member.email)

      {:ok, view, _html} = live(log_in_user(conn, member), ~p"/household")

      refute has_element?(view, "#invite-form")
      assert has_element?(view, "#my-invitation-#{invitation.id}", "Elsewhere")

      view |> element("#my-invitation-#{invitation.id} button", "Decline") |> render_click()

      refute has_element?(view, "#my-invitations")
    end
  end

  describe "invited user without a household" do
    setup %{conn: conn} do
      %{scope: owner_scope, household: household} =
        household_fixture(user_fixture(), %{name: "Hosts"})

      invitee = user_fixture()

      %{
        conn: log_in_user(conn, invitee),
        owner_scope: owner_scope,
        household: household,
        invitee: invitee
      }
    end

    test "joins automatically when there is one invitation", %{
      conn: conn,
      owner_scope: owner_scope,
      invitee: invitee
    } do
      invite(owner_scope, invitee.email)

      assert {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/welcome")
      assert path == ~p"/plan"
      assert flash["info"] == "You've joined Hosts."

      {:ok, plan, _html} = live(conn, ~p"/plan")
      assert has_element?(plan, "#household-name", "Hosts")
    end

    test "chooses between several invitations", %{
      conn: conn,
      owner_scope: owner_scope,
      invitee: invitee
    } do
      invite(owner_scope, invitee.email)
      %{scope: other_scope} = household_fixture(user_fixture(), %{name: "Others"})
      other = invite(other_scope, invitee.email)

      {:ok, view, _html} = live(conn, ~p"/welcome")
      assert has_element?(view, "#invitations", "Hosts")
      assert has_element?(view, "#invitations", "Others")

      assert {:error, {:redirect, %{to: "/plan"}}} =
               view |> element("#invitation-#{other.id} button", "Join") |> render_click()

      assert Repo.reload!(invitee).household_id == other_scope.household.id
    end

    test "declining leaves the create form", %{
      conn: conn,
      owner_scope: owner_scope,
      invitee: invitee
    } do
      invite(owner_scope, invitee.email)
      %{scope: other_scope} = household_fixture()
      other = invite(other_scope, invitee.email)

      {:ok, view, _html} = live(conn, ~p"/welcome")
      view |> element("#invitation-#{other.id} button", "Decline") |> render_click()

      refute has_element?(view, "#invitation-#{other.id}")
      assert has_element?(view, "#household-form")
    end
  end

  describe "creating a household with invitations" do
    setup :register_and_log_in_user

    test "invites the listed addresses", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/welcome")

      view
      |> form("#household-form", household: %{name: "With guests", usually_feeding: 3})
      |> render_submit(%{"invites" => "a@example.com, B@example.com\nb@example.com"})

      flash = assert_redirect(view, "/plan")
      assert flash["info"] == "Welcome to With guests. 2 invitations sent."
      assert Accounts.get_user_by_email("a@example.com")
      assert Accounts.get_user_by_email("b@example.com")
    end

    test "refuses invalid addresses before creating anything", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/welcome")

      html =
        view
        |> form("#household-form", household: %{name: "Typo", usually_feeding: 3})
        |> render_submit(%{"invites" => "good@example.com, bad-address"})

      assert html =~ "not valid email addresses: bad-address"
      refute Repo.reload!(user).household_id
    end
  end

  test "end to end: a new address is invited, logs in from the email and joins", %{conn: conn} do
    %{scope: owner_scope, household: household} =
      household_fixture(user_fixture(), %{name: "Hosts"})

    token =
      extract_user_token(fn url_fun ->
        {:ok, _} =
          Households.invite(owner_scope, %{email: "newcomer@example.com"}, url_fun, "https://x")

        assert_received {:email, %{to: [{"", "newcomer@example.com"}]} = email}
        {:ok, email}
      end)

    conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == ~p"/"

    assert {:error, {:redirect, %{to: "/plan"}}} = live(conn, ~p"/welcome")
    assert Accounts.get_user_by_email("newcomer@example.com").household_id == household.id
  end
end
