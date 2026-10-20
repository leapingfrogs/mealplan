defmodule Mealplan.Households do
  @moduledoc """
  Households and their meal slots. Every function takes the caller's
  `Mealplan.Accounts.Scope` and only ever touches that scope's household.
  """
  import Ecto.Query

  alias Mealplan.Accounts
  alias Mealplan.Accounts.Scope
  alias Mealplan.Accounts.User
  alias Mealplan.Households.Household
  alias Mealplan.Households.Invitation
  alias Mealplan.Households.MealSlot
  alias Mealplan.RateLimit
  alias Mealplan.Repo

  @doc """
  Subscribes the caller to changes in its household
  (`{:household_changed, what}` messages).
  """
  def subscribe(%Scope{household: %Household{id: id}}) do
    Phoenix.PubSub.subscribe(Mealplan.PubSub, topic(id))
  end

  @doc "Tells every member's open pages that something in the household changed."
  def broadcast(%Scope{household: %Household{id: id}}, message), do: broadcast_to(id, message)

  defp broadcast_to(household_id, message) do
    Phoenix.PubSub.broadcast(Mealplan.PubSub, topic(household_id), message)
  end

  defp topic(household_id), do: "household:#{household_id}"

  @doc "True when the scope's user owns its household."
  def owner?(%Scope{user: %User{id: user_id}, household: %Household{owner_id: user_id}}), do: true
  def owner?(%Scope{}), do: false

  @doc """
  Updates the household's name, usual number of servings or time zone.
  Owner only. Members' open pages receive `{:household_updated, household}`.
  """
  def update_household(%Scope{household: %Household{} = household} = scope, attrs) do
    if owner?(scope) do
      with {:ok, household} <- household |> Household.changeset(attrs) |> Repo.update() do
        :ok = broadcast(scope, {:household_updated, household})
        {:ok, household}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc "Lists the household's members, the owner first, then by email."
  def list_members(%Scope{household: %Household{id: household_id, owner_id: owner_id}}) do
    Repo.all(
      from u in User,
        where: u.household_id == ^household_id,
        order_by: [desc: u.id == ^owner_id, asc: u.email]
    )
  end

  ## Membership

  @doc """
  Removes a member from the household (owner only; not the owner). Their
  open pages are sent to /welcome via `{:member_removed, user_id}`.
  """
  def remove_member(%Scope{household: %Household{} = household} = scope, member_id) do
    cond do
      not owner?(scope) -> {:error, :unauthorized}
      member_id == household.owner_id -> {:error, :owner}
      true -> unlink(household, member_id)
    end
  end

  @doc """
  Leaves the household. The owner must transfer ownership first (or delete
  the household).
  """
  def leave_household(
        %Scope{user: %User{id: user_id}, household: %Household{} = household} = scope
      ) do
    if owner?(scope), do: {:error, :owner_must_transfer}, else: unlink(household, user_id)
  end

  defp unlink(household, user_id) do
    from(u in User, where: u.id == ^user_id and u.household_id == ^household.id)
    |> Repo.update_all(set: [household_id: nil])
    |> case do
      {1, _} ->
        :ok = broadcast_to(household.id, {:member_removed, user_id})
        :ok

      {0, _} ->
        {:error, :not_found}
    end
  end

  @doc "Makes another member the owner (owner only)."
  def transfer_ownership(%Scope{household: %Household{} = household} = scope, member_id) do
    cond do
      not owner?(scope) ->
        {:error, :unauthorized}

      not Repo.exists?(
        from u in User, where: u.id == ^member_id and u.household_id == ^household.id
      ) ->
        {:error, :not_found}

      true ->
        household = household |> Ecto.Changeset.change(owner_id: member_id) |> Repo.update!()
        :ok = broadcast(scope, {:household_updated, household})
        {:ok, household}
    end
  end

  @doc """
  Deletes the household and everything in it (owner only), once
  `confirmation` matches its name. Members' open pages are sent to /welcome
  via `:household_deleted`.
  """
  def delete_household(%Scope{household: %Household{} = household} = scope, confirmation) do
    cond do
      not owner?(scope) ->
        {:error, :unauthorized}

      String.trim(to_string(confirmation)) != household.name ->
        {:error, :confirmation_mismatch}

      true ->
        # Members are unlinked and household data cascades in the database.
        {:ok, _} = Repo.delete(household)
        :ok = broadcast(scope, :household_deleted)
        :ok
    end
  end

  @doc "Returns a changeset for the household form."
  def change_household(%Household{} = household \\ %Household{}, attrs \\ %{}) do
    Household.changeset(household, attrs)
  end

  @doc """
  Creates a household owned by the scope's user, makes them its first member
  and adds the default meal slots.

  Fails with `{:error, :already_in_household}` if the user already belongs to
  one (including a concurrent create).
  """
  def create_household(%Scope{user: %User{} = user, household: nil}, attrs) do
    # Any {:error, _} below rolls the whole transaction back.
    Repo.transact(fn ->
      with {:ok, household} <-
             Repo.insert(Household.changeset(%Household{owner_id: user.id}, attrs)),
           :ok <- join(user, household) do
        Enum.each(default_slots(household), &Repo.insert!/1)
        {:ok, household}
      end
    end)
  end

  def create_household(%Scope{household: %Household{}}, _attrs),
    do: {:error, :already_in_household}

  # Only succeeds if the user still has no household, which also guards
  # against two creates racing.
  defp join(user, household) do
    from(u in User, where: u.id == ^user.id and is_nil(u.household_id))
    |> Repo.update_all(set: [household_id: household.id])
    |> case do
      {1, _} -> :ok
      {0, _} -> {:error, :already_in_household}
    end
  end

  defp default_slots(household) do
    MealSlot.defaults()
    |> Enum.with_index()
    |> Enum.map(fn {{key, name}, position} ->
      %MealSlot{household_id: household.id, name: name, default_key: key, position: position}
    end)
  end

  @doc "Lists the household's active meal slots in day order."
  def list_meal_slots(%Scope{household: %Household{id: household_id}}) do
    Repo.all(
      from s in MealSlot,
        where: s.household_id == ^household_id and is_nil(s.archived_at),
        order_by: [asc: s.position, asc: s.inserted_at]
    )
  end

  ## Invitations

  # Per household, so an owner can't use invitations to flood addresses.
  @invitations_per_hour 20

  @doc "Returns a changeset for the invite form."
  def change_invitation(attrs \\ %{}), do: Invitation.email_changeset(%Invitation{}, attrs)

  @doc """
  Invites an email address to the scope's household (owner only), creating an
  account for it if there is none, and emails it a magic login link.

  Inviting an address that already has an open invitation renews it and sends
  the email again. The result doesn't reveal whether the address had an
  account. `magic_link_url_fun` turns a login token into a URL; `login_url`
  is where to get a fresh link.
  """
  def invite(%Scope{} = scope, attrs, magic_link_url_fun, login_url) do
    changeset = Map.put(change_invitation(attrs), :action, :insert)
    email = Ecto.Changeset.get_field(changeset, :email)

    cond do
      not owner?(scope) ->
        {:error, :unauthorized}

      not changeset.valid? ->
        {:error, changeset}

      member_email?(scope, email) ->
        {:error, Ecto.Changeset.add_error(changeset, :email, "is already a member")}

      rate_limited?(scope) ->
        {:error, :rate_limited}

      true ->
        send_invitation(scope, email, magic_link_url_fun, login_url)
    end
  end

  defp send_invitation(scope, email, magic_link_url_fun, login_url) do
    with {:ok, user} <- Accounts.get_or_create_user_by_email(email),
         {:ok, invitation} <- upsert_invitation(scope, email) do
      details = %{
        invitation_id: invitation.id,
        household_name: scope.household.name,
        inviter_email: scope.user.email,
        expires_at: invitation.expires_at,
        login_url: login_url
      }

      :ok = broadcast(scope, {:household_changed, :invitations})

      case Accounts.deliver_household_invitation(user, details, magic_link_url_fun) do
        {:ok, _email} -> {:ok, invitation}
        {:error, _reason} -> {:error, :delivery_failed}
      end
    end
  end

  defp upsert_invitation(%Scope{household: household, user: inviter}, email) do
    now = DateTime.utc_now(:second)
    expires_at = DateTime.shift(now, day: Invitation.validity_days())

    Repo.insert(
      %Invitation{
        household_id: household.id,
        invited_by_id: inviter.id,
        email: email,
        expires_at: expires_at
      },
      on_conflict: [set: [expires_at: expires_at, invited_by_id: inviter.id, updated_at: now]],
      conflict_target:
        {:unsafe_fragment,
         "(household_id, email) WHERE accepted_at IS NULL AND declined_at IS NULL AND revoked_at IS NULL"},
      returning: true
    )
  end

  defp member_email?(%Scope{household: %Household{id: household_id}}, email) do
    Repo.exists?(from u in User, where: u.household_id == ^household_id and u.email == ^email)
  end

  defp rate_limited?(%Scope{household: %Household{id: household_id}}) do
    match?(
      {:deny, _},
      RateLimit.hit(
        "household_invitations:#{household_id}",
        to_timeout(hour: 1),
        @invitations_per_hour
      )
    )
  end

  @doc "Lists the household's pending invitations, newest first."
  def list_pending_invitations(%Scope{household: %Household{id: household_id}}) do
    Repo.all(
      from i in pending_invitations(),
        where: i.household_id == ^household_id,
        order_by: [desc: i.updated_at]
    )
  end

  @doc """
  Lists the pending invitations addressed to the scope's user, with their
  household and inviter loaded.
  """
  def list_invitations_for_user(%Scope{user: %User{email: email}}) do
    Repo.all(
      from i in pending_invitations(),
        where: i.email == ^email,
        order_by: [asc: i.inserted_at],
        preload: [:household, :invited_by]
    )
  end

  @doc """
  Accepts an invitation addressed to the scope's user, who must not belong to
  a household yet. Returns the household joined.
  """
  def accept_invitation(%Scope{household: %Household{}}, _invitation_id),
    do: {:error, :already_in_household}

  def accept_invitation(%Scope{user: %User{} = user}, invitation_id) do
    fn ->
      with {:ok, invitation} <- fetch_invitation_for(user, invitation_id, lock: true),
           :ok <- join(user, %Household{id: invitation.household_id}),
           {:ok, _invitation} <- close_invitation(invitation, :accepted_at) do
        {:ok, Repo.get!(Household, invitation.household_id)}
      end
    end
    |> Repo.transact()
    |> tap(fn
      {:ok, household} -> broadcast_to(household.id, {:household_changed, :members})
      _error -> :ok
    end)
  end

  @doc "Declines an invitation addressed to the scope's user."
  def decline_invitation(%Scope{user: %User{} = user}, invitation_id) do
    with {:ok, invitation} <- fetch_invitation_for(user, invitation_id),
         {:ok, invitation} <- close_invitation(invitation, :declined_at) do
      :ok = Accounts.delete_invitation_tokens(invitation.id)
      :ok = broadcast_to(invitation.household_id, {:household_changed, :invitations})
      {:ok, invitation}
    end
  end

  @doc "Revokes one of the household's pending invitations (owner only)."
  def revoke_invitation(%Scope{household: %Household{id: household_id}} = scope, invitation_id) do
    with true <- owner?(scope) || {:error, :unauthorized},
         %Invitation{} = invitation <-
           Repo.one(
             from i in pending_invitations(),
               where: i.household_id == ^household_id and i.id == ^invitation_id
           ) || {:error, :not_found},
         {:ok, invitation} <- close_invitation(invitation, :revoked_at) do
      :ok = Accounts.delete_invitation_tokens(invitation.id)
      :ok = broadcast(scope, {:household_changed, :invitations})
      {:ok, invitation}
    end
  end

  defp fetch_invitation_for(user, invitation_id, opts \\ []) do
    query =
      from i in pending_invitations(), where: i.id == ^invitation_id and i.email == ^user.email

    query = if opts[:lock], do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      %Invitation{} = invitation -> {:ok, invitation}
      nil -> {:error, :not_found}
    end
  end

  defp close_invitation(invitation, field) do
    invitation
    |> Ecto.Changeset.change([{field, DateTime.utc_now(:second)}])
    |> Repo.update()
  end

  defp pending_invitations do
    now = DateTime.utc_now(:second)

    from i in Invitation,
      where:
        is_nil(i.accepted_at) and is_nil(i.declined_at) and is_nil(i.revoked_at) and
          i.expires_at > ^now
  end
end
