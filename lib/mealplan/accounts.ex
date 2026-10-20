defmodule Mealplan.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  ## Database getters
  alias Mealplan.Accounts.User
  alias Mealplan.Accounts.UserNotifier
  alias Mealplan.Accounts.UserToken
  alias Mealplan.Repo

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """

  ## User registration

  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Invites a user by email. Registration is invite-only, so this is the only
  way accounts are created.

  Registers the user and emails them a magic link; following it confirms
  the account and logs them in.

  ## Options

    * `:admin` - make the user an administrator. Defaults to `false`.

  ## Examples

      iex> invite_user("new@example.com", magic_link_url_fun)
      {:ok, %User{}}

      iex> invite_user("taken@example.com", magic_link_url_fun)
      {:error, %Ecto.Changeset{}}

  """
  def invite_user(email, magic_link_url_fun, opts \\ [])
      when is_function(magic_link_url_fun, 1) do
    with {:ok, user} <-
           %User{admin: Keyword.get(opts, :admin, false)}
           |> User.email_changeset(%{email: email})
           |> Repo.insert(),
         {:ok, _email} <- deliver_login_instructions(user, magic_link_url_fun) do
      {:ok, user}
    end
  end

  ## Settings

  @doc """
  Grants or revokes administrator rights.

  Not exposed in the UI; used from the console or release tasks.
  """
  def set_admin(%User{} = user, admin?) when is_boolean(admin?) do
    user
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:admin, admin?)
    |> Repo.update()
  end

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.shift(DateTime.utc_now(), minute: minutes))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Mealplan.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Mealplan.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  ## Session
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """

  ## Token helper

  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Returns the account for `email`, creating an unconfirmed one if there is
  none (used for household invitations). Safe against a concurrent create.
  """
  def get_or_create_user_by_email(email) when is_binary(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, user}

      nil ->
        case register_user(%{email: email}) do
          {:ok, user} -> {:ok, user}
          {:error, changeset} -> retry_after_race(email, changeset)
        end
    end
  end

  defp retry_after_race(email, changeset) do
    case get_user_by_email(email) do
      %User{} = user -> {:ok, user}
      nil -> {:error, changeset}
    end
  end

  @doc """
  Emails `user` an invitation to join a household, with a magic login link.

  New (unconfirmed) accounts get a link that works for the invitation's whole
  lifetime, replacing any earlier link for the same invitation; existing
  accounts get the usual short-lived link, since they can always log in
  normally.

  `details` has `:invitation_id`, `:household_name`, `:inviter_email`,
  `:expires_at` and `:login_url` (where to ask for a fresh link).
  """
  def deliver_household_invitation(%User{} = user, details, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    long_lived? = is_nil(user.confirmed_at)

    {encoded_token, user_token} =
      if long_lived? do
        :ok = delete_invitation_tokens(details.invitation_id)
        UserToken.build_invitation_token(user, details.invitation_id)
      else
        UserToken.build_email_token(user, "login")
      end

    Repo.insert!(user_token)

    UserNotifier.deliver_household_invitation(
      user,
      magic_link_url_fun.(encoded_token),
      Map.put(details, :link_lasts_until_expiry, long_lived?)
    )
  end

  @doc """
  Invalidates an invitation's login links (when it's renewed, revoked or
  declined).
  """
  def delete_invitation_tokens(invitation_id) do
    context = UserToken.invitation_context(invitation_id)
    Repo.delete_all(from(t in UserToken, where: t.context == ^context))
    :ok
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
