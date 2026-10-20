defmodule Mealplan.Households do
  @moduledoc """
  Households and their meal slots. Every function takes the caller's
  `Mealplan.Accounts.Scope` and only ever touches that scope's household.
  """
  import Ecto.Query

  alias Mealplan.Accounts.Scope
  alias Mealplan.Accounts.User
  alias Mealplan.Households.Household
  alias Mealplan.Households.MealSlot
  alias Mealplan.Repo

  @doc """
  Subscribes the caller to changes in its household
  (`{:household_changed, what}` messages).
  """
  def subscribe(%Scope{household: %Household{id: id}}) do
    Phoenix.PubSub.subscribe(Mealplan.PubSub, topic(id))
  end

  @doc "Tells every member's open pages that something in the household changed."
  def broadcast(%Scope{household: %Household{id: id}}, message) do
    Phoenix.PubSub.broadcast(Mealplan.PubSub, topic(id), message)
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
end
