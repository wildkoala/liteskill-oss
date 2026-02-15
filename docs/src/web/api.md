# REST API

Liteskill provides a JSON REST API for programmatic access to conversations and groups. All API routes are under the `/api` prefix.

## Authentication

API requests use session-based authentication via cookies. The session must contain a valid `user_id`. Unauthenticated requests receive a 401 response:

```json
{"error": "authentication required"}
```

To authenticate, first call the password login endpoint:

```
POST /auth/login
Content-Type: application/json

{"email": "user@example.com", "password": "your-password"}
```

The response sets a session cookie that must be included in subsequent API requests.

## Rate Limiting

All API routes are rate limited at 1000 requests per 60-second window. When exceeded, the server returns a 429 status with a `retry-after` header:

```
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 60

{"error": "Too many requests"}
```

## Conversation Endpoints

### List Conversations

```
GET /api/conversations
GET /api/conversations?limit=20&offset=0
```

**Query Parameters:**

| Parameter | Type | Default | Max | Description |
|-----------|------|---------|-----|-------------|
| `limit` | integer | 20 | 100 | Number of conversations to return |
| `offset` | integer | 0 | 10000 | Number of conversations to skip |

**Response (200):**

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "My Conversation",
      "model_id": "anthropic.claude-sonnet-4-20250514-v1:0",
      "status": "active",
      "message_count": 5,
      "last_message_at": "2025-01-15T10:30:00Z",
      "parent_conversation_id": null,
      "inserted_at": "2025-01-15T09:00:00Z",
      "updated_at": "2025-01-15T10:30:00Z"
    }
  ]
}
```

### Create Conversation

```
POST /api/conversations
Content-Type: application/json

{
  "title": "New Conversation",
  "model_id": "anthropic.claude-sonnet-4-20250514-v1:0",
  "system_prompt": "You are a helpful assistant."
}
```

**Request Body:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `title` | string | No | "New Conversation" | Conversation title |
| `model_id` | string | No | null | LLM model identifier |
| `system_prompt` | string | No | null | System prompt for the LLM |

**Response (201):**

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "New Conversation",
    "model_id": "anthropic.claude-sonnet-4-20250514-v1:0",
    "status": "active",
    "message_count": 0,
    "last_message_at": null,
    "parent_conversation_id": null,
    "inserted_at": "2025-01-15T09:00:00Z",
    "updated_at": "2025-01-15T09:00:00Z"
  }
}
```

### Show Conversation

```
GET /api/conversations/:id
```

Returns the conversation with all messages. The user must have access (owner, direct ACL, or group-based ACL).

**Response (200):**

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "My Conversation",
    "model_id": "anthropic.claude-sonnet-4-20250514-v1:0",
    "system_prompt": "You are a helpful assistant.",
    "status": "active",
    "message_count": 2,
    "last_message_at": "2025-01-15T10:30:00Z",
    "parent_conversation_id": null,
    "messages": [
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "role": "user",
        "content": "Hello!",
        "status": "sent",
        "model_id": null,
        "stop_reason": null,
        "input_tokens": null,
        "output_tokens": null,
        "total_tokens": null,
        "latency_ms": null,
        "position": 1,
        "inserted_at": "2025-01-15T10:00:00Z"
      },
      {
        "id": "660e8400-e29b-41d4-a716-446655440002",
        "role": "assistant",
        "content": "Hi there! How can I help you today?",
        "status": "complete",
        "model_id": "anthropic.claude-sonnet-4-20250514-v1:0",
        "stop_reason": "end_turn",
        "input_tokens": 10,
        "output_tokens": 15,
        "total_tokens": 25,
        "latency_ms": 1200,
        "position": 2,
        "inserted_at": "2025-01-15T10:00:01Z"
      }
    ],
    "inserted_at": "2025-01-15T09:00:00Z",
    "updated_at": "2025-01-15T10:30:00Z"
  }
}
```

### Send Message

```
POST /api/conversations/:conversation_id/messages
Content-Type: application/json

{
  "content": "What is the weather like today?"
}
```

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `content` | string | Yes | The message content |

**Response (201):**

```json
{
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440003",
    "role": "user",
    "content": "What is the weather like today?",
    "status": "sent",
    "model_id": null,
    "stop_reason": null,
    "input_tokens": null,
    "output_tokens": null,
    "total_tokens": null,
    "latency_ms": null,
    "position": 3,
    "inserted_at": "2025-01-15T10:31:00Z"
  }
}
```

Note: This endpoint queues the user message. The LLM response is generated asynchronously via the streaming pipeline and will appear when listing messages.

### Fork Conversation

```
POST /api/conversations/:conversation_id/fork
Content-Type: application/json

{
  "at_position": 3
}
```

Creates a new conversation branching from the specified message position.

**Request Body:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `at_position` | integer | No | 1 | Message position to fork from |

**Response (201):**

```json
{
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440000",
    "title": "My Conversation (fork)",
    "model_id": "anthropic.claude-sonnet-4-20250514-v1:0",
    "status": "active",
    "message_count": 3,
    "last_message_at": "2025-01-15T10:31:00Z",
    "parent_conversation_id": "550e8400-e29b-41d4-a716-446655440000",
    "inserted_at": "2025-01-15T10:35:00Z",
    "updated_at": "2025-01-15T10:35:00Z"
  }
}
```

### Grant Access

```
POST /api/conversations/:conversation_id/acls
Content-Type: application/json

{
  "user_id": "880e8400-e29b-41d4-a716-446655440000",
  "role": "manager"
}
```

Grants another user access to the conversation. Only the conversation owner can grant access.

**Request Body:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `user_id` | string (UUID) | Yes | -- | User to grant access to |
| `role` | string | No | "manager" | Access role |

**Response (201):**

```json
{
  "data": {
    "id": "990e8400-e29b-41d4-a716-446655440000",
    "role": "manager",
    "user_id": "880e8400-e29b-41d4-a716-446655440000"
  }
}
```

### Revoke Access

```
DELETE /api/conversations/:conversation_id/acls/:target_user_id
```

Revokes a user's access to the conversation. Only the conversation owner can revoke access.

**Response (204):** No content

### Leave Conversation

```
DELETE /api/conversations/:conversation_id/membership
```

Removes the current user's access to a shared conversation. Cannot be used by the conversation owner.

**Response (204):** No content

## Group Endpoints

### List Groups

```
GET /api/groups
```

Returns groups where the current user is a member.

**Response (200):**

```json
{
  "data": [
    {
      "id": "aa0e8400-e29b-41d4-a716-446655440000",
      "name": "Engineering",
      "created_by": "550e8400-e29b-41d4-a716-446655440000",
      "inserted_at": "2025-01-10T08:00:00Z",
      "updated_at": "2025-01-10T08:00:00Z"
    }
  ]
}
```

### Create Group

```
POST /api/groups
Content-Type: application/json

{
  "name": "Engineering"
}
```

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Group name |

**Response (201):**

```json
{
  "data": {
    "id": "aa0e8400-e29b-41d4-a716-446655440000",
    "name": "Engineering",
    "created_by": "550e8400-e29b-41d4-a716-446655440000",
    "inserted_at": "2025-01-10T08:00:00Z",
    "updated_at": "2025-01-10T08:00:00Z"
  }
}
```

### Show Group

```
GET /api/groups/:id
```

**Response (200):**

```json
{
  "data": {
    "id": "aa0e8400-e29b-41d4-a716-446655440000",
    "name": "Engineering",
    "created_by": "550e8400-e29b-41d4-a716-446655440000",
    "inserted_at": "2025-01-10T08:00:00Z",
    "updated_at": "2025-01-10T08:00:00Z"
  }
}
```

### Delete Group

```
DELETE /api/groups/:id
```

Deletes a group. Only the group creator can delete it.

**Response (204):** No content

### Add Member

```
POST /api/groups/:group_id/members
Content-Type: application/json

{
  "user_id": "880e8400-e29b-41d4-a716-446655440000",
  "role": "member"
}
```

**Request Body:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `user_id` | string (UUID) | Yes | -- | User to add |
| `role` | string | No | "member" | Membership role |

**Response (201):**

```json
{
  "data": {
    "id": "bb0e8400-e29b-41d4-a716-446655440000",
    "group_id": "aa0e8400-e29b-41d4-a716-446655440000",
    "user_id": "880e8400-e29b-41d4-a716-446655440000",
    "role": "member"
  }
}
```

### Remove Member

```
DELETE /api/groups/:group_id/members/:user_id
```

**Response (204):** No content

## Error Responses

All errors follow a consistent JSON format.

### 401 Unauthorized

```json
{"error": "authentication required"}
```

Returned when no valid session is present.

### 403 Forbidden

```json
{"error": "forbidden"}
```

Returned when the user does not have permission for the requested operation (e.g., revoking access on a conversation they do not own).

### 404 Not Found

```json
{"error": "not found"}
```

Returned when the requested resource does not exist or the user has no access to it.

### 422 Unprocessable Entity

For validation errors with changeset details:

```json
{
  "error": "validation failed",
  "details": {
    "email": ["has already been taken"],
    "password": ["should be at least 12 character(s)"]
  }
}
```

For other domain errors:

```json
{"error": "cannot leave own conversation"}
```

### 429 Too Many Requests

```json
{"error": "Too many requests"}
```

Includes a `Retry-After` header with the number of seconds to wait.
