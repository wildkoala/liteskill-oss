# Authentication

Liteskill supports two authentication strategies: password-based auth and OpenID Connect (OIDC). Both strategies establish a server-side session with the user's ID, which is used for all subsequent request authorization.

## Auth Strategies

### Password Auth

#### Registration

```
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "name": "Alice",
  "password": "securepassword123"
}
```

- Passwords are hashed with Argon2 before storage
- Registration can be gated via `Settings.registration_open?()` -- when closed, returns 403
- On success, the user is automatically logged in (session cookie set)

#### Login

```
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword123"
}
```

- The special username `"admin"` is resolved to the configured admin email address, allowing admin login with just `"admin"` as the email field
- On success, sets the `user_id` in the session and returns user data
- On failure, returns 401 with `{"error": "invalid credentials"}`

### OIDC (Ueberauth)

Liteskill uses the [Ueberauth](https://hex.pm/packages/ueberauth) library with the OIDC strategy for single sign-on.

#### Flow

1. **Redirect**: `GET /auth/:provider` initiates the OIDC redirect to the identity provider
2. **Callback**: `GET /auth/:provider/callback` or `POST /auth/:provider/callback` handles the token exchange

#### User Data Extraction

On successful OIDC callback, the following fields are extracted from the auth response:

| Field | Source |
|-------|--------|
| `email` | `auth.info.email` |
| `name` | `auth.info.name` |
| `avatar_url` | `auth.info.image` |
| `oidc_sub` | `auth.uid` |
| `oidc_issuer` | `auth.extra.raw_info.userinfo["iss"]` |
| `oidc_claims` | `auth.extra.raw_info.userinfo` |

The callback calls `Accounts.find_or_create_from_oidc/1`, which either finds an existing user by their OIDC subject identifier or creates a new account.

#### Configuration

OIDC is configured via environment variables (see [Environment Variables](../configuration/environment-variables.md)):

```
OIDC_ISSUER=https://accounts.google.com
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
```

When `OIDC_CLIENT_ID` is not set, the OIDC provider routes remain defined but the strategy is not configured.

### Session Bridge

LiveView cannot set session cookies directly. To handle authentication from LiveView forms (login/register), a signed token bridge is used:

1. The LiveView form generates a signed Phoenix token containing the `user_id` (TTL: 60 seconds)
2. The browser is redirected to `GET /auth/session?token=<signed_token>`
3. `SessionController.create/2` verifies the token and establishes the session cookie
4. The user is redirected to `/`

This approach allows LiveView authentication forms to work without a full-page form submission while maintaining secure session establishment.

If the token is expired or invalid, the user is redirected to `/login` with a flash error.

#### Logout

```
DELETE /auth/logout
```

Clears the session and redirects to `/login`.

## Plugs

### Auth Plug

Module: `LiteskillWeb.Plugs.Auth`

A dual-purpose plug that supports two actions:

#### `fetch_current_user`

Loads the current user from the session into `conn.assigns.current_user`:

1. Reads `user_id` from the session
2. If present, looks up the user via `Accounts.get_user/1`
3. Assigns the user (or `nil`) to `conn.assigns.current_user`

Used in the `:api` pipeline to make the current user available to all API routes.

#### `require_authenticated_user`

Checks that `conn.assigns.current_user` is present:

- If authenticated, passes the connection through unchanged
- If not authenticated, returns a 401 JSON response and halts the connection

Used in the `:require_auth` pipeline for protected API routes.

## LiveAuth Hooks

Module: `LiteskillWeb.Plugs.LiveAuth`

LiveView `on_mount` hooks that protect LiveView routes. These are specified in `live_session` declarations in the router.

### `require_authenticated`

Used by the `:chat` live session for all main application routes.

1. Reads `user_id` from the LiveView session
2. Looks up the user via `Accounts.get_user/1`
3. If the user has `setup_required?` set, redirects to `/setup`
4. Otherwise, assigns the user to the socket

If no user is found, redirects to `/login`.

### `require_admin`

Used by the `:admin` live session for admin panel routes.

1. Loads the user from the session
2. Checks `User.admin?/1`
3. If admin, assigns the user and continues
4. If not admin, redirects to `/`

### `require_setup_needed`

Used by the `:setup` live session for the first-time setup wizard.

1. Looks up the admin user by the configured admin email
2. If the admin exists and has `setup_required?` set, allows access
3. Otherwise, redirects to `/` (setup already complete)

### `redirect_if_authenticated`

Used by the `:auth` live session for login/register pages.

1. First checks if the admin account needs setup -- if so, redirects to `/setup`
2. If a `user_id` is in the session and the user exists, redirects to `/`
3. Otherwise, allows access to the login/register page
