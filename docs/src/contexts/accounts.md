# Accounts Context

Module: `Liteskill.Accounts`

The Accounts context manages user records. Users can be created via OIDC authentication or password-based registration.

## User Schema

`Liteskill.Accounts.User`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key, auto-generated |
| `email` | `:string` | Unique, required |
| `name` | `:string` | Display name |
| `avatar_url` | `:string` | |
| `oidc_sub` | `:string` | OIDC subject identifier |
| `oidc_issuer` | `:string` | OIDC issuer URL |
| `oidc_claims` | `:map` | Raw OIDC claims |
| `password_hash` | `:string` | Argon2 hash |
| `role` | `:string` | `"user"` or `"admin"` (default: `"user"`) |
| `force_password_change` | `:boolean` | Forces password change on next login |
| `preferences` | `:map` | User preferences (default: `%{}`) |

Root admin email: `admin@liteskill.local`

## User Management

### `ensure_admin_user()`

Boot-time function. Ensures the root admin user (`admin@liteskill.local`) exists. Creates the user if missing; forces role to `"admin"` if it was changed.

```elixir
ensure_admin_user() :: User.t()
```

### `find_or_create_from_oidc(attrs)`

Idempotent OIDC user creation. Finds an existing user by `oidc_sub` + `oidc_issuer`, or creates a new one. Safe to call on every login callback.

```elixir
find_or_create_from_oidc(%{
  oidc_sub: String.t(),     # required
  oidc_issuer: String.t(),  # required
  email: String.t(),
  name: String.t(),
  avatar_url: String.t(),
  oidc_claims: map()
})
:: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
```

### `register_user(attrs)`

Password-based user registration. Password must be 12-72 characters.

```elixir
register_user(%{email: String.t(), name: String.t(), password: String.t()})
:: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
```

### `authenticate_by_email_password(email, password)`

Authenticates a user by email and password.

```elixir
authenticate_by_email_password(String.t(), String.t())
:: {:ok, User.t()} | {:error, :invalid_credentials}
```

### `get_user_by_email(email)`

```elixir
get_user_by_email(String.t()) :: User.t() | nil
```

### `get_user!(id)`

Gets a user by ID. Raises `Ecto.NoResultsError` if not found.

```elixir
get_user!(binary_id) :: User.t()
```

### `get_user(id)`

Gets a user by ID. Returns `nil` if not found.

```elixir
get_user(binary_id) :: User.t() | nil
```

### `list_users()`

Returns all users ordered by email.

```elixir
list_users() :: [User.t()]
```

### `search_users(query, opts \\ [])`

Searches users by name or email using ILIKE matching.

```elixir
search_users(String.t(), keyword()) :: [User.t()]
```

Options:
- `:limit` -- max results (default: 10)
- `:exclude` -- list of user IDs to exclude (default: `[]`)

### `update_user_role(user_id, role)`

Updates a user's role. Prevents demoting the root admin (`admin@liteskill.local`).

```elixir
update_user_role(binary_id, String.t())
:: {:ok, User.t()} | {:error, :not_found | :cannot_demote_root_admin}
```

## Password Management

### `change_password(user, current_password, new_password)`

Changes a user's password. Requires verification of the current password. Clears `force_password_change` flag.

```elixir
change_password(User.t(), String.t(), String.t())
:: {:ok, User.t()} | {:error, :invalid_current_password}
```

### `setup_admin_password(user, password)`

First-time admin password setup. Does not require a current password.

```elixir
setup_admin_password(User.t(), String.t())
:: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
```

### `set_temporary_password(user, password)`

Sets a temporary password for a user (admin action). Sets `force_password_change: true` so the user must change their password on next login.

```elixir
set_temporary_password(User.t(), String.t())
:: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
```

## Preferences

### `update_preferences(user, new_prefs)`

Merges new keys into the user's existing preferences map.

```elixir
update_preferences(User.t(), map())
:: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
```

## Invitations

### `create_invitation(email, admin_user_id)`

Creates an invitation for the given email address, issued by an admin user.

```elixir
create_invitation(String.t(), binary_id)
:: {:ok, Invitation.t()} | {:error, Ecto.Changeset.t()}
```

### `get_invitation_by_token(token)`

Gets an invitation by its token, preloading the creator.

```elixir
get_invitation_by_token(String.t()) :: Invitation.t() | nil
```

### `list_invitations()`

Lists all invitations ordered by most recent first, preloading the creator.

```elixir
list_invitations() :: [Invitation.t()]
```

### `accept_invitation(token, attrs)`

Accepts an invitation inside a transaction. Uses `FOR UPDATE` lock on the invitation row to prevent concurrent acceptance. Creates the user with the invitation's email and the provided password/name, then marks the invitation as used.

```elixir
accept_invitation(String.t(), %{name: String.t(), password: String.t()})
:: {:ok, User.t()} | {:error, :not_found | :already_used | :expired | Ecto.Changeset.t()}
```

### `revoke_invitation(id)`

Revokes (deletes) a pending invitation. Returns an error if the invitation has already been used.

```elixir
revoke_invitation(binary_id)
:: {:ok, Invitation.t()} | {:error, :not_found | :already_used}
```
