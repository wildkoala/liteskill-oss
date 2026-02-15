# Schedules

Schedules provide cron-like recurring execution for Agent Studio runs. You can configure a schedule to automatically create and execute runs on a periodic basis, enabling automated reporting, monitoring, and analysis workflows.

## Schedule Configuration

Each schedule defines a recurring execution pattern and the run parameters to use each time it fires.

### Schedule Fields

| Field | Description |
|---|---|
| `name` | Schedule name (unique per user) |
| `description` | Optional description |
| `cron_expression` | Standard 5-field cron expression (minute, hour, day-of-month, month, day-of-week) |
| `timezone` | Timezone for cron evaluation (default: `UTC`) |
| `enabled` | Whether the schedule is active |
| `status` | `active` or `inactive` |
| `prompt` | The prompt to use for each generated run |
| `topology` | Execution topology for generated runs (default: `pipeline`) |
| `context` | Additional context passed to each run as JSON |
| `timeout_ms` | Timeout for generated runs (default: 1,800,000 ms / 30 minutes) |
| `max_iterations` | Maximum iterations for generated runs (default: 50) |
| `team_definition_id` | The team that executes each generated run |
| `last_run_at` | Timestamp of the most recent execution |
| `next_run_at` | Computed timestamp of the next scheduled execution |

### Cron Expressions

Schedules use standard 5-field cron expressions:

```
* * * * *
| | | | |
| | | | +-- day of week (0-6, Sunday=0)
| | | +---- month (1-12)
| | +------ day of month (1-31)
| +-------- hour (0-23)
+---------- minute (0-59)
```

Supported syntax:

| Syntax | Example | Description |
|---|---|---|
| `*` | `* * * * *` | Every minute |
| Exact value | `30 9 * * *` | At 9:30 AM |
| Step | `*/15 * * * *` | Every 15 minutes |
| List | `0 9,17 * * *` | At 9:00 AM and 5:00 PM |

6-field expressions are also accepted (the 6th field is ignored).

### Timezone Support

The `timezone` field controls how the cron expression is interpreted. The system:

1. Converts the current UTC time to the specified timezone
2. Evaluates the cron expression in local time
3. Converts the next match back to UTC for storage

This ensures schedules fire at the expected local time regardless of DST transitions.

## ScheduleTick GenServer

The `ScheduleTick` GenServer runs in the application supervision tree and periodically checks for due schedules.

### Tick Cycle

1. On startup, `ScheduleTick` schedules its first tick
2. Every **60 seconds**, it fires a `:tick` message
3. On each tick, it queries for all enabled schedules where `next_run_at <= now`
4. For each due schedule, it enqueues a `ScheduleWorker` Oban job
5. Errors during the tick are caught and logged without crashing the GenServer

The tick interval ensures schedules fire within approximately one minute of their target time.

## ScheduleWorker

The `ScheduleWorker` is an Oban job that handles the actual execution when a schedule fires.

### Execution Flow

1. Load the schedule and verify it is still enabled
2. Create a new run with parameters from the schedule:
   - Name: `"ScheduleName -- YYYY-MM-DD HH:MM"` (timestamped for identification)
   - Prompt, topology, context, timeout, and team from the schedule
3. Update the schedule's timestamps:
   - Set `last_run_at` to the current time
   - Compute and set `next_run_at` from the cron expression
4. Start the runner asynchronously via `Task.Supervisor`

### Deduplication

The worker uses Oban's unique job feature with a 55-second uniqueness period keyed on `schedule_id`. This prevents duplicate executions if the ScheduleTick fires multiple times for the same schedule within a single tick window.

### Error Handling

- If the schedule is not found, the worker logs a warning and returns `:ok` (no retry)
- If the schedule is disabled, it skips execution and returns `:ok`
- If run creation fails, the worker logs an error and returns the error for Oban retry
- The worker has `max_attempts: 1` -- it does not retry on failure

## CRUD Operations

Schedules are managed through the `Schedules` context:

- **Create**: `Schedules.create_schedule/1` -- automatically computes `next_run_at` if the schedule is enabled and no `next_run_at` is provided
- **Update**: `Schedules.update_schedule/3` -- owner-only
- **Delete**: `Schedules.delete_schedule/2` -- owner-only
- **Toggle**: `Schedules.toggle_schedule/2` -- flips the `enabled` flag
- **List**: `Schedules.list_schedules/1` -- returns all schedules the user owns or has ACL access to
- **Get**: `Schedules.get_schedule/2` -- with authorization check

## ACL Sharing

Schedules support the same ACL sharing system used by other Liteskill entities:

- **Owner**: Full control including editing, deletion, and toggling
- **Shared access**: View the schedule and its generated runs

Share schedules with specific users to give them visibility into automated workflows and their outputs.
