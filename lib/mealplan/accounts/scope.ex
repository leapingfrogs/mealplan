defmodule Mealplan.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Mealplan.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Mealplan.Accounts.User
  alias Mealplan.Households.Household

  defstruct user: nil, household: nil

  @doc """
  Creates a scope for the given user, including their household when it has
  been loaded (the session lookup always loads it).

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user, household: loaded_household(user)}
  end

  def for_user(nil), do: nil

  defp loaded_household(%User{household: %Household{} = household}), do: household
  defp loaded_household(_user), do: nil
end
