defmodule Mealplan.Households.Invitation do
  @moduledoc """
  An invitation for an email address to join a household. Pending while not
  accepted, declined or revoked and before `expires_at`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mealplan.Accounts.User
  alias Mealplan.Households.Household

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "household_invitations" do
    field :email, :string
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :declined_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :household, Household
    belongs_to :invited_by, User

    timestamps(type: :utc_datetime)
  end

  @validity_days 7

  @doc "How long an invitation stays valid."
  def validity_days, do: @validity_days

  @doc """
  Validates the address being invited. Household, inviter and expiry are set
  by the caller.
  """
  def email_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email])
    |> update_change(:email, &normalize/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
  end

  defp normalize(nil), do: nil
  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
