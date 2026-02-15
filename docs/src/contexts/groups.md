# Groups Context

Module: `Liteskill.Groups`

The Groups context manages groups and their memberships. Groups are used for group-based ACL authorization across entity types.

## Schemas

### Group

`Liteskill.Groups.Group`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `name` | `:string` | Required |
| `created_by` | `:binary_id` | FK to User, set programmatically |

### GroupMembership

`Liteskill.Groups.GroupMembership`

| Field | Type | Notes |
|---|---|---|
| `id` | `:binary_id` | Primary key |
| `role` | `:string` | `"owner"` or `"member"` |
| `group_id` | `:binary_id` | FK to Group |
| `user_id` | `:binary_id` | FK to User |

## User-Facing API

### `create_group(name, creator_id)`

Creates a group and automatically adds the creator as an owner member.

```elixir
create_group(String.t(), binary_id)
:: {:ok, Group.t()} | {:error, term()}
```

### `list_groups(user_id)`

Lists groups the user is a member of.

```elixir
list_groups(binary_id) :: [Group.t()]
```

### `get_group(id, user_id)`

Gets a group if the user is a member of it.

```elixir
get_group(binary_id, binary_id)
:: {:ok, Group.t()} | {:error, :not_found}
```

### `add_member(group_id, requester_id, target_user_id, role \\ "member")`

Adds a member to a group. Requires the requester to be the group creator.

```elixir
add_member(binary_id, binary_id, binary_id, String.t())
:: {:ok, GroupMembership.t()} | {:error, :not_found | :forbidden}
```

### `remove_member(group_id, requester_id, target_user_id)`

Removes a member from a group. Requires the requester to be the group creator. Cannot remove the owner.

```elixir
remove_member(binary_id, binary_id, binary_id)
:: {:ok, GroupMembership.t()} | {:error, :not_found | :forbidden | :cannot_remove_owner}
```

### `leave_group(group_id, user_id)`

User leaves a group voluntarily. The group owner (creator) cannot leave.

```elixir
leave_group(binary_id, binary_id)
:: {:ok, GroupMembership.t()} | {:error, :not_found | :creator_cannot_leave}
```

### `delete_group(group_id, user_id)`

Deletes a group. Only the group creator can delete it.

```elixir
delete_group(binary_id, binary_id)
:: {:ok, Group.t()} | {:error, :not_found | :forbidden}
```

## Admin API

These functions bypass creator and membership checks. Intended for admin use only.

### `list_all_groups()`

Lists all groups ordered by name, preloading memberships and creator.

```elixir
list_all_groups() :: [Group.t()]
```

### `admin_get_group(id)`

Gets a group by ID without membership checks.

```elixir
admin_get_group(binary_id)
:: {:ok, Group.t()} | {:error, :not_found}
```

### `admin_list_members(group_id)`

Lists all memberships for a group, preloading user associations.

```elixir
admin_list_members(binary_id) :: [GroupMembership.t()]
```

### `admin_add_member(group_id, user_id, role \\ "member")`

Adds a member without authorization checks.

```elixir
admin_add_member(binary_id, binary_id, String.t())
:: {:ok, GroupMembership.t()} | {:error, Ecto.Changeset.t()}
```

### `admin_remove_member(group_id, user_id)`

Removes a member without authorization checks.

```elixir
admin_remove_member(binary_id, binary_id)
:: {:ok, GroupMembership.t()} | {:error, :not_found}
```

### `admin_delete_group(group_id)`

Deletes a group without authorization checks.

```elixir
admin_delete_group(binary_id)
:: {:ok, Group.t()} | {:error, :not_found}
```
