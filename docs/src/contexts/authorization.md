# Authorization Context

Module: `Liteskill.Authorization`

Centralized authorization context for all entity types. Provides access checks, role queries, ACL management, and composable query helpers that other contexts delegate to.

## Role Hierarchy

```
viewer < editor < manager < owner
```

| Role | Permissions |
|---|---|
| `viewer` | Read-only access |
| `editor` | Can edit content (wiki_space only for now) |
| `manager` | Edit + grant/revoke viewer/editor/manager access |
| `owner` | Full control (delete, demote anyone, transfer ownership) |

## Supported Entity Types

- `agent_definition`
- `conversation`
- `data_source`
- `run`
- `llm_model`
- `llm_provider`
- `mcp_server`
- `report`
- `schedule`
- `team_definition`
- `wiki_space`

## EntityAcl Schema

`Liteskill.Authorization.EntityAcl`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `entity_type` | `:string` | One of the supported entity types |
| `entity_id` | `:binary_id` | ID of the entity being protected |
| `role` | `:string` | Default: `"viewer"` |
| `user_id` | `:binary_id` | Nullable -- set for direct user ACLs |
| `group_id` | `:binary_id` | Nullable -- set for group-based ACLs |

Either `user_id` or `group_id` is set, never both.

## Access Checks

### `has_access?(entity_type, entity_id, user_id)`

Returns `true` if the user has any access to the entity via direct ACL or group-based ACL.

```elixir
has_access?(String.t(), binary_id, binary_id) :: boolean()
```

### `get_role(entity_type, entity_id, user_id)`

Returns the highest role the user holds on the entity across all direct and group-based ACLs.

```elixir
get_role(String.t(), binary_id, binary_id)
:: {:ok, String.t()} | {:error, :no_access}
```

### `can_manage?(entity_type, entity_id, user_id)`

Returns `true` if the user has `"manager"` or `"owner"` role.

```elixir
can_manage?(String.t(), binary_id, binary_id) :: boolean()
```

### `can_edit?(entity_type, entity_id, user_id)`

Returns `true` if the user has `"editor"`, `"manager"`, or `"owner"` role.

```elixir
can_edit?(String.t(), binary_id, binary_id) :: boolean()
```

### `is_owner?(entity_type, entity_id, user_id)`

Returns `true` if the user has `"owner"` role.

```elixir
is_owner?(String.t(), binary_id, binary_id) :: boolean()
```

## ACL Management

### `create_owner_acl(entity_type, entity_id, user_id)`

Creates the initial owner ACL when a resource is created. Called automatically by context modules during creation.

```elixir
create_owner_acl(String.t(), binary_id, binary_id)
:: {:ok, EntityAcl.t()} | {:error, Ecto.Changeset.t()}
```

### `grant_access(entity_type, entity_id, grantor_id, grantee_user_id, role)`

Grants access to a user. Grantor must be owner or manager. Nobody can grant `"owner"` role -- ownership is only set at creation. For wiki spaces, managers can only grant `"viewer"` or `"editor"`.

```elixir
grant_access(String.t(), binary_id, binary_id, binary_id, String.t())
:: {:ok, EntityAcl.t()} | {:error, :cannot_grant_owner | :forbidden | :no_access}
```

### `grant_group_access(entity_type, entity_id, grantor_id, group_id, role)`

Grants access to a group. Same permission rules as `grant_access/5`.

```elixir
grant_group_access(String.t(), binary_id, binary_id, binary_id, String.t())
:: {:ok, EntityAcl.t()} | {:error, :cannot_grant_owner | :forbidden | :no_access}
```

### `update_role(entity_type, entity_id, grantor_id, target_user_id, new_role)`

Updates the role of an existing ACL entry. Grantor must be owner or manager. Cannot change to or from `"owner"`.

```elixir
update_role(String.t(), binary_id, binary_id, binary_id, String.t())
:: {:ok, EntityAcl.t()} | {:error, :not_found | :cannot_modify_owner | :cannot_grant_owner | :forbidden}
```

### `revoke_access(entity_type, entity_id, revoker_id, target_user_id)`

Revokes a user's access. Revoker must be owner or manager. Cannot revoke owners.

```elixir
revoke_access(String.t(), binary_id, binary_id, binary_id)
:: {:ok, EntityAcl.t()} | {:error, :not_found | :cannot_revoke_owner | :forbidden | :no_access}
```

### `revoke_group_access(entity_type, entity_id, revoker_id, group_id)`

Revokes a group's access. Same permission rules as `revoke_access/4`.

```elixir
revoke_group_access(String.t(), binary_id, binary_id, binary_id)
:: {:ok, EntityAcl.t()} | {:error, :not_found | :cannot_revoke_owner | :forbidden | :no_access}
```

### `leave(entity_type, entity_id, user_id)`

User voluntarily leaves an entity. Owners cannot leave.

```elixir
leave(String.t(), binary_id, binary_id)
:: {:ok, EntityAcl.t()} | {:error, :not_found | :owner_cannot_leave}
```

### `list_acls(entity_type, entity_id)`

Lists all ACLs for an entity, preloading user and group associations. Ordered by role (descending) then insertion time (ascending).

```elixir
list_acls(String.t(), binary_id) :: [EntityAcl.t()]
```

### `accessible_entity_ids(entity_type, user_id)`

Returns a subquery of entity IDs the user can access for the given type. Used by other contexts to filter their list queries.

```elixir
accessible_entity_ids(String.t(), binary_id) :: Ecto.Query.t()
```

## Helper Functions

### `authorize_owner(entity, user_id)`

Struct-level ownership check via the `:user_id` field. Returns `{:ok, entity}` if the user owns it, `{:error, :forbidden}` otherwise.

```elixir
authorize_owner(%{user_id: binary_id}, binary_id)
:: {:ok, struct()} | {:error, :forbidden}
```

### `create_with_owner_acl(changeset, entity_type, preloads \\ [])`

Inserts a changeset inside a transaction, creates an owner ACL for the resulting entity, and preloads the given associations.

```elixir
create_with_owner_acl(Ecto.Changeset.t(), String.t(), [atom()])
:: {:ok, struct()} | {:error, Ecto.Changeset.t()}
```

### `verify_ownership(entity_type, entity_id, user_id)`

Verifies that the user owns the given entity by checking the `user_id` field on the entity record.

```elixir
verify_ownership(String.t(), binary_id, binary_id) :: :ok | :error
```
