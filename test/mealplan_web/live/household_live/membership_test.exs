defmodule MealplanWeb.HouseholdLive.MembershipTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.AccountsFixtures
  import Mealplan.HouseholdsFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Accounts.User
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Repo

  setup %{conn: conn} do
    %{user: owner, household: household, scope: owner_scope} =
      household_fixture(user_fixture(), %{name: "Home"})

    %{user: member} = member_fixture(household)

    %{
      owner_conn: log_in_user(conn, owner),
      member_conn: log_in_user(Phoenix.ConnTest.build_conn(), member),
      owner: owner,
      member: member,
      household: household,
      owner_scope: owner_scope
    }
  end

  test "the owner removes a member, whose open pages are sent to /welcome",
       %{owner_conn: owner_conn, member_conn: member_conn, member: member} do
    {:ok, member_plan, _html} = live(member_conn, ~p"/plan")
    {:ok, view, _html} = live(owner_conn, ~p"/household")

    view |> element("#member-#{member.id} button", "Remove") |> render_click()

    refute has_element?(view, "#member-#{member.id}")
    assert_redirect(member_plan, ~p"/welcome")
    assert Repo.get!(User, member.id).household_id == nil
  end

  test "a member leaves", %{member_conn: member_conn, member: member} do
    {:ok, view, _html} = live(member_conn, ~p"/household")

    view |> element("#leave-household") |> render_click()

    flash = assert_redirect(view, ~p"/welcome")
    assert flash["info"] == "You've left Home."
    assert Repo.get!(User, member.id).household_id == nil
  end

  test "the owner can't leave but is told how", %{owner_conn: owner_conn} do
    {:ok, view, _html} = live(owner_conn, ~p"/household")

    refute has_element?(view, "#leave-household")
    assert render(view) =~ "To leave, make someone else the owner first."
  end

  test "the owner transfers ownership; both pages switch roles live",
       %{owner_conn: owner_conn, member_conn: member_conn, member: member, household: household} do
    {:ok, member_view, _html} = live(member_conn, ~p"/household")
    refute has_element?(member_view, "#household-form")

    {:ok, view, _html} = live(owner_conn, ~p"/household")
    view |> element("#member-#{member.id} button", "Make owner") |> render_click()

    assert Repo.get!(Household, household.id).owner_id == member.id
    refute has_element?(view, "#household-form")
    assert has_element?(view, "#leave-household")
    assert has_element?(member_view, "#household-form")
    assert has_element?(member_view, "#member-#{member.id} .badge", "owner")
  end

  describe "deleting the household" do
    test "refuses a mismatched name", %{owner_conn: owner_conn, household: household} do
      {:ok, view, _html} = live(owner_conn, ~p"/household")

      html = view |> form("#delete-form", %{confirmation: "Hom"}) |> render_submit()

      assert html =~ "doesn&#39;t match. Nothing was deleted."
      assert Repo.get(Household, household.id)
    end

    test "deletes it and sends every member to /welcome",
         %{owner_conn: owner_conn, member_conn: member_conn, household: household} do
      {:ok, member_plan, _html} = live(member_conn, ~p"/plan")
      {:ok, view, _html} = live(owner_conn, ~p"/household")

      view |> form("#delete-form", %{confirmation: "Home"}) |> render_submit()

      assert assert_redirect(view, ~p"/welcome")["info"] == "Home was deleted."
      assert assert_redirect(member_plan, ~p"/welcome")["info"] == "Home was deleted."
      refute Repo.get(Household, household.id)
    end

    test "is only offered to the owner", %{member_conn: member_conn} do
      {:ok, view, _html} = live(member_conn, ~p"/household")
      refute has_element?(view, "#delete-household")
    end
  end

  test "leaving to accept an invitation elsewhere", %{member_conn: member_conn, member: member} do
    %{scope: other_scope, household: other} =
      household_fixture(user_fixture(), %{name: "Elsewhere"})

    {:ok, _} =
      Households.invite(other_scope, %{email: member.email}, &"https://x/#{&1}", "https://x")

    {:ok, view, _html} = live(member_conn, ~p"/household")
    assert has_element?(view, "#my-invitations", "Elsewhere")
    view |> element("#leave-household") |> render_click()
    assert_redirect(view, ~p"/welcome")

    assert {:error, {:redirect, %{to: "/plan"}}} = live(member_conn, ~p"/welcome")
    assert Repo.get!(User, member.id).household_id == other.id
  end
end
