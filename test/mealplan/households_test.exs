defmodule Mealplan.HouseholdsTest do
  use Mealplan.DataCase, async: true

  import Mealplan.AccountsFixtures
  import Mealplan.HouseholdsFixtures

  alias Mealplan.Accounts
  alias Mealplan.Accounts.Scope
  alias Mealplan.Accounts.User
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Households.MealSlot

  describe "create_household/2" do
    test "creates the household owned by the user, who becomes its member" do
      user = user_fixture()

      assert {:ok, %Household{} = household} =
               Households.create_household(Scope.for_user(user), %{
                 name: "  The Davies household  ",
                 time_zone: "Europe/London",
                 usually_feeding: 4
               })

      assert household.name == "The Davies household"
      assert household.owner_id == user.id
      assert household.time_zone == "Europe/London"
      assert household.usually_feeding == 4
      assert Repo.get!(User, user.id).household_id == household.id
    end

    test "adds the default meal slots in day order" do
      %{scope: scope} = household_fixture()

      assert [
               %MealSlot{name: "Breakfast", default_key: "breakfast", position: 0},
               %MealSlot{name: "Lunch", default_key: "lunch", position: 1},
               %MealSlot{name: "Dinner", default_key: "dinner", position: 2},
               %MealSlot{name: "Snack", default_key: "snack", position: 3}
             ] = Households.list_meal_slots(scope)
    end

    test "validates name, usually feeding and time zone" do
      scope = Scope.for_user(user_fixture())

      assert {:error, changeset} =
               Households.create_household(scope, %{
                 name: " ",
                 usually_feeding: 0,
                 time_zone: "Mars/Olympus"
               })

      assert %{
               name: ["can't be blank"],
               usually_feeding: ["must be greater than 0"],
               time_zone: ["is not a known time zone"]
             } = errors_on(changeset)

      assert {:error, changeset} =
               Households.create_household(
                 scope,
                 valid_household_attributes(name: String.duplicate("a", 81), usually_feeding: 51)
               )

      assert %{name: [_], usually_feeding: ["must be less than or equal to 50"]} =
               errors_on(changeset)

      assert Repo.aggregate(Household, :count) == 0
    end

    test "refuses a user who already has a household" do
      %{scope: scope} = household_fixture()

      assert Households.create_household(scope, valid_household_attributes()) ==
               {:error, :already_in_household}
    end

    test "refuses, and rolls back, when the user joined a household since the scope was built" do
      user = user_fixture()
      stale_scope = Scope.for_user(user)
      household_fixture(user)

      assert Households.create_household(stale_scope, valid_household_attributes()) ==
               {:error, :already_in_household}

      assert Repo.aggregate(Household, :count) == 1
      assert Repo.aggregate(MealSlot, :count) == 4
    end
  end

  describe "owner?/1" do
    test "is true only for the household's owner" do
      %{scope: owner_scope, household: household} = household_fixture()
      %{scope: member_scope} = member_fixture(household)

      assert Households.owner?(owner_scope)
      refute Households.owner?(member_scope)
    end
  end

  describe "update_household/2" do
    test "lets the owner update the details and tells the household" do
      %{scope: scope} = household_fixture()
      :ok = Households.subscribe(scope)

      assert {:ok, household} =
               Households.update_household(scope, %{
                 name: "Renamed",
                 usually_feeding: 6,
                 time_zone: "America/New_York"
               })

      assert %{name: "Renamed", usually_feeding: 6, time_zone: "America/New_York"} = household
      assert_receive {:household_updated, %Household{name: "Renamed"}}
    end

    test "validates like creation" do
      %{scope: scope} = household_fixture()

      assert {:error, changeset} =
               Households.update_household(scope, %{name: "", time_zone: "Nowhere/Land"})

      assert %{name: ["can't be blank"], time_zone: ["is not a known time zone"]} =
               errors_on(changeset)
    end

    test "refuses members who aren't the owner" do
      %{household: household} = household_fixture(user_fixture(), %{name: "Original"})
      %{scope: member_scope} = member_fixture(household)

      assert Households.update_household(member_scope, %{name: "Hijacked"}) ==
               {:error, :unauthorized}

      assert Repo.get!(Household, household.id).name == "Original"
    end
  end

  describe "list_members/1" do
    test "lists the household's members, owner first" do
      owner = user_fixture(email: "zed@example.com")
      %{scope: scope, household: household} = household_fixture(owner)
      %{user: member} = member_fixture(household)
      household_fixture()

      assert Enum.map(Households.list_members(scope), & &1.id) == [owner.id, member.id]
    end
  end

  describe "invite/4" do
    alias Mealplan.Households.Invitation

    # Fixtures send their own login emails; drop them before asserting.
    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    defp invite(scope, email),
      do:
        Households.invite(
          scope,
          %{email: email},
          &"https://mealplan.test/users/log-in/#{&1}",
          "https://mealplan.test/users/log-in"
        )

    test "creates an account for a new address, records the invitation and emails a login link" do
      %{scope: scope, household: household} =
        household_fixture(user_fixture(), %{name: "The Davies"})

      flush_emails()
      :ok = Households.subscribe(scope)

      assert {:ok, %Invitation{} = invitation} = invite(scope, " New.Person@Example.com ")

      assert invitation.email == "new.person@example.com"
      assert invitation.household_id == household.id
      assert DateTime.diff(invitation.expires_at, DateTime.utc_now(), :day) in 6..7

      assert %User{household_id: nil, confirmed_at: nil} =
               Accounts.get_user_by_email("new.person@example.com")

      assert_received {:email, email}
      assert email.to == [{"", "new.person@example.com"}]
      assert email.subject =~ "invited you to The Davies"
      assert email.text_body =~ "https://mealplan.test/users/log-in/"
      assert_receive {:household_changed, :invitations}

      assert [%Invitation{id: id}] = Households.list_pending_invitations(scope)
      assert id == invitation.id
    end

    test "invites an existing account without creating another" do
      %{scope: scope} = household_fixture()
      existing = user_fixture()
      flush_emails()

      assert {:ok, _} = invite(scope, existing.email)
      assert Repo.aggregate(from(u in User, where: u.email == ^existing.email), :count) == 1
      assert_received {:email, %{to: [{"", to}]}}
      assert to == existing.email
    end

    test "inviting again renews the open invitation and resends the email" do
      %{scope: scope} = household_fixture()
      {:ok, first} = invite(scope, "again@example.com")
      assert_received {:email, _}

      Repo.update_all(from(i in Invitation, where: i.id == ^first.id),
        set: [expires_at: ~U[2020-01-01 00:00:00Z]]
      )

      assert {:ok, second} = invite(scope, "AGAIN@example.com")
      assert second.id == first.id
      assert DateTime.after?(second.expires_at, DateTime.utc_now())
      assert Repo.aggregate(Invitation, :count) == 1
      assert_received {:email, _}
    end

    test "rejects invalid addresses and existing members" do
      %{scope: scope, user: owner, household: household} = household_fixture()
      %{user: member} = member_fixture(household)
      flush_emails()

      assert {:error, changeset} = invite(scope, "not an email")
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)

      for email <- [owner.email, String.upcase(member.email)] do
        assert {:error, changeset} = invite(scope, email)
        assert %{email: ["is already a member"]} = errors_on(changeset)
      end

      refute_received {:email, _}
    end

    test "is for owners only" do
      %{household: household} = household_fixture()
      %{scope: member_scope} = member_fixture(household)

      assert invite(member_scope, "someone@example.com") == {:error, :unauthorized}
      assert Repo.aggregate(Invitation, :count) == 0
    end

    test "limits invitations per household" do
      %{scope: scope} = household_fixture()

      for n <- 1..20, do: assert({:ok, _} = invite(scope, "person#{n}@example.com"))
      assert invite(scope, "one-too-many@example.com") == {:error, :rate_limited}
    end
  end

  describe "invitation login links" do
    alias Mealplan.Accounts.UserToken
    alias Mealplan.Households.Invitation

    setup do
      %{scope: scope} = household_fixture(user_fixture(), %{name: "Hosts"})
      flush_emails()
      %{scope: scope}
    end

    defp invite_and_get_link(scope, email) do
      {:ok, invitation} =
        Households.invite(scope, %{email: email}, &"https://x/log-in/#{&1}", "https://x/log-in")

      assert_received {:email, %{text_body: body}}
      [_, token] = Regex.run(~r{https://x/log-in/([\w-]+)}, body)
      {invitation, token, body}
    end

    defp age_tokens(user, days) do
      at = DateTime.shift(DateTime.utc_now(:second), day: -days)
      Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id), set: [inserted_at: at])
    end

    test "a new account's link lasts as long as the invitation", %{scope: scope} do
      {_invitation, token, body} = invite_and_get_link(scope, "new@example.com")
      user = Accounts.get_user_by_email("new@example.com")

      assert body =~ "The link and the invitation are valid until"
      refute body =~ "15 minutes"

      age_tokens(user, 6)
      assert Accounts.get_user_by_magic_link_token(token).id == user.id

      age_tokens(user, 8)
      refute Accounts.get_user_by_magic_link_token(token)
    end

    test "works once: logging in confirms the account and spends the link", %{scope: scope} do
      {_invitation, token, _body} = invite_and_get_link(scope, "once@example.com")

      assert {:ok, {%User{confirmed_at: %DateTime{}}, _tokens}} =
               Accounts.login_user_by_magic_link(token)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
    end

    test "inviting again replaces the earlier link", %{scope: scope} do
      {_invitation, old, _body} = invite_and_get_link(scope, "again@example.com")
      {_invitation, new, _body} = invite_and_get_link(scope, "again@example.com")

      refute Accounts.get_user_by_magic_link_token(old)
      assert Accounts.get_user_by_magic_link_token(new)
    end

    test "revoking or declining the invitation kills the link", %{scope: scope} do
      {invitation, token, _body} = invite_and_get_link(scope, "revoked@example.com")
      assert {:ok, _} = Households.revoke_invitation(scope, invitation.id)
      refute Accounts.get_user_by_magic_link_token(token)

      {invitation, token, _body} = invite_and_get_link(scope, "declined@example.com")
      user = Accounts.get_user_by_email("declined@example.com")
      assert {:ok, _} = Households.decline_invitation(Scope.for_user(user), invitation.id)
      refute Accounts.get_user_by_magic_link_token(token)
    end

    test "an existing account gets the usual short-lived login link", %{scope: scope} do
      existing = user_fixture()
      flush_emails()
      {_invitation, token, body} = invite_and_get_link(scope, existing.email)

      assert body =~ "15 minutes"
      age_tokens(existing, 1)
      refute Accounts.get_user_by_magic_link_token(token)
    end

    test "the link's validity matches the invitation's" do
      assert UserToken.invitation_validity_in_days() == Invitation.validity_days()
    end
  end

  describe "invitations for the invited user" do
    alias Mealplan.Households.Invitation

    setup do
      %{scope: owner_scope, household: household} =
        household_fixture(user_fixture(), %{name: "Hosts"})

      invitee = user_fixture()

      {:ok, invitation} =
        Households.invite(owner_scope, %{email: invitee.email}, &"https://x/#{&1}", "https://x")

      %{
        owner_scope: owner_scope,
        household: household,
        invitee: invitee,
        scope: Scope.for_user(invitee),
        invitation: invitation
      }
    end

    test "list_invitations_for_user/1 lists pending invitations with household and inviter",
         %{scope: scope, invitation: invitation, owner_scope: owner_scope} do
      assert [%Invitation{id: id, household: %Household{name: "Hosts"}, invited_by: inviter}] =
               Households.list_invitations_for_user(scope)

      assert id == invitation.id
      assert inviter.id == owner_scope.user.id
    end

    test "expired, revoked and declined invitations are not pending", %{
      scope: scope,
      owner_scope: owner_scope,
      invitation: invitation
    } do
      Repo.update_all(from(i in Invitation, where: i.id == ^invitation.id),
        set: [expires_at: ~U[2020-01-01 00:00:00Z]]
      )

      assert Households.list_invitations_for_user(scope) == []
      assert Households.list_pending_invitations(owner_scope) == []
      assert Households.accept_invitation(scope, invitation.id) == {:error, :not_found}
    end

    test "accept_invitation/2 joins the household and tells its members",
         %{
           scope: scope,
           invitee: invitee,
           household: household,
           owner_scope: owner_scope,
           invitation: invitation
         } do
      :ok = Households.subscribe(owner_scope)

      assert {:ok, %Household{id: id}} = Households.accept_invitation(scope, invitation.id)
      assert id == household.id
      assert Repo.get!(User, invitee.id).household_id == household.id
      assert Repo.get!(Invitation, invitation.id).accepted_at
      assert_receive {:household_changed, :members}

      assert Households.accept_invitation(scope, invitation.id) == {:error, :not_found}
    end

    test "accept_invitation/2 refuses users who already have a household", %{
      invitee: invitee,
      invitation: invitation
    } do
      %{scope: scope} = household_fixture(invitee)

      assert Households.accept_invitation(scope, invitation.id) == {:error, :already_in_household}
    end

    test "only the addressee can accept or decline", %{invitation: invitation} do
      stranger_scope = Scope.for_user(user_fixture())

      assert Households.accept_invitation(stranger_scope, invitation.id) == {:error, :not_found}
      assert Households.decline_invitation(stranger_scope, invitation.id) == {:error, :not_found}
    end

    test "decline_invitation/2 closes it", %{scope: scope, invitation: invitation} do
      assert {:ok, %Invitation{declined_at: %DateTime{}}} =
               Households.decline_invitation(scope, invitation.id)

      assert Households.list_invitations_for_user(scope) == []
    end

    test "revoke_invitation/2 is owner only and closes it",
         %{owner_scope: owner_scope, household: household, scope: scope, invitation: invitation} do
      %{scope: member_scope} = member_fixture(household)

      assert Households.revoke_invitation(member_scope, invitation.id) == {:error, :unauthorized}

      assert {:ok, %Invitation{revoked_at: %DateTime{}}} =
               Households.revoke_invitation(owner_scope, invitation.id)

      assert Households.list_invitations_for_user(scope) == []
      assert Households.revoke_invitation(owner_scope, invitation.id) == {:error, :not_found}
    end
  end

  describe "remove_member/2 and leave_household/1" do
    setup do
      %{scope: owner_scope, household: household, user: owner} = household_fixture()
      %{scope: member_scope, user: member} = member_fixture(household)
      :ok = Households.subscribe(owner_scope)

      %{
        owner_scope: owner_scope,
        owner: owner,
        member_scope: member_scope,
        member: member,
        household: household
      }
    end

    test "the owner removes a member, who is told", %{owner_scope: owner_scope, member: member} do
      assert Households.remove_member(owner_scope, member.id) == :ok
      assert Repo.get!(User, member.id).household_id == nil
      assert_receive {:member_removed, id}
      assert id == member.id
    end

    test "only the owner removes, and never themselves",
         %{owner_scope: owner_scope, owner: owner, member_scope: member_scope} do
      assert Households.remove_member(member_scope, owner.id) == {:error, :unauthorized}
      assert Households.remove_member(owner_scope, owner.id) == {:error, :owner}
      assert Households.remove_member(owner_scope, user_fixture().id) == {:error, :not_found}
    end

    test "a member leaves; the owner must transfer first",
         %{owner_scope: owner_scope, member_scope: member_scope, member: member} do
      assert Households.leave_household(member_scope) == :ok
      assert Repo.get!(User, member.id).household_id == nil
      assert_receive {:member_removed, _}

      assert Households.leave_household(owner_scope) == {:error, :owner_must_transfer}
    end
  end

  describe "transfer_ownership/2" do
    test "the owner makes a member the owner" do
      %{scope: owner_scope, household: household, user: owner} = household_fixture()
      %{scope: member_scope, user: member} = member_fixture(household)
      :ok = Households.subscribe(owner_scope)

      assert Households.transfer_ownership(member_scope, owner.id) == {:error, :unauthorized}
      assert Households.transfer_ownership(owner_scope, user_fixture().id) == {:error, :not_found}

      assert {:ok, %Household{owner_id: new_owner}} =
               Households.transfer_ownership(owner_scope, member.id)

      assert new_owner == member.id
      assert_receive {:household_updated, %Household{owner_id: ^new_owner}}

      new_scope = %{owner_scope | household: Repo.get!(Household, household.id)}
      refute Households.owner?(new_scope)
      assert Households.leave_household(new_scope) == :ok
    end
  end

  describe "delete_household/2" do
    alias Mealplan.Households.Invitation

    test "needs the owner and the exact name, then removes everything" do
      %{scope: owner_scope, household: household, user: owner} =
        household_fixture(user_fixture(), %{name: "Doomed"})

      %{scope: member_scope, user: member} = member_fixture(household)

      {:ok, _} =
        Households.invite(
          owner_scope,
          %{email: "pending@example.com"},
          &"https://x/#{&1}",
          "https://x"
        )

      :ok = Households.subscribe(owner_scope)

      assert Households.delete_household(member_scope, "Doomed") == {:error, :unauthorized}

      assert Households.delete_household(owner_scope, "doomed") ==
               {:error, :confirmation_mismatch}

      assert Repo.get(Household, household.id)

      assert Households.delete_household(owner_scope, " Doomed ") == :ok
      assert_receive :household_deleted

      refute Repo.get(Household, household.id)
      assert Repo.get!(User, owner.id).household_id == nil
      assert Repo.get!(User, member.id).household_id == nil

      assert Repo.aggregate(from(s in MealSlot, where: s.household_id == ^household.id), :count) ==
               0

      assert Repo.aggregate(from(i in Invitation, where: i.household_id == ^household.id), :count) ==
               0
    end
  end

  describe "list_meal_slots/1" do
    test "only lists the scope's household's active slots" do
      %{scope: scope, household: household} = household_fixture()
      %{scope: other_scope} = household_fixture()

      archived = Repo.get_by!(MealSlot, household_id: household.id, default_key: "snack")
      Repo.update!(Ecto.Changeset.change(archived, archived_at: DateTime.utc_now(:second)))

      assert Enum.map(Households.list_meal_slots(scope), & &1.name) == [
               "Breakfast",
               "Lunch",
               "Dinner"
             ]

      assert length(Households.list_meal_slots(other_scope)) == 4
    end
  end

  describe "meal slot constraints" do
    test "names are unique per household, ignoring case, among active slots" do
      %{household: household} = household_fixture()
      %{household: other} = household_fixture()

      assert_raise Ecto.ConstraintError, ~r/meal_slots_household_id_name_index/, fn ->
        Repo.insert!(%MealSlot{household_id: household.id, name: "DINNER", position: 9})
      end

      assert %MealSlot{} =
               Repo.insert!(%MealSlot{household_id: other.id, name: "Pudding", position: 9})
    end

    test "default_key must be one of the defaults" do
      %{household: household} = household_fixture()

      assert_raise Ecto.ConstraintError, ~r/default_key_valid/, fn ->
        Repo.insert!(%MealSlot{
          household_id: household.id,
          name: "Brunch",
          position: 9,
          default_key: "brunch"
        })
      end
    end
  end

  describe "subscribe/1 and broadcast/2" do
    test "deliver messages to the same household only" do
      %{scope: scope} = household_fixture()
      %{scope: other_scope} = household_fixture()

      :ok = Households.subscribe(scope)
      :ok = Households.broadcast(scope, {:household_changed, :test})
      :ok = Households.broadcast(other_scope, {:household_changed, :other})

      assert_receive {:household_changed, :test}
      refute_receive {:household_changed, :other}
    end
  end

  describe "the session scope" do
    test "includes the user's household" do
      %{user: user, household: household} = household_fixture()
      token = Accounts.generate_user_session_token(user)

      {session_user, _} = Accounts.get_user_by_session_token(token)
      assert %Scope{household: %Household{id: id}} = Scope.for_user(session_user)
      assert id == household.id
    end

    test "has no household for a user without one" do
      token = Accounts.generate_user_session_token(user_fixture())

      {session_user, _} = Accounts.get_user_by_session_token(token)
      assert %Scope{household: nil} = Scope.for_user(session_user)
    end
  end
end
