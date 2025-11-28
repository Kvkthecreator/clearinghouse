# App Events Architecture

> **Status**: Canonical
> **Last Updated**: 2024-11-28

## Overview

The `app_events` table is the **single source of truth** for realtime notifications in yarnnn. All other event mechanisms have been deprecated and removed.

## Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Python Backend │         │    app_events    │         │   Frontend      │
│  (EventService) │ ──────► │     (Supabase)   │ ──────► │ (Realtime Sub)  │
└─────────────────┘         └──────────────────┘         └─────────────────┘
                                    │
                                    ▼
                            Supabase Realtime
                            (via postgres_changes)
```

## Table Schema

```sql
CREATE TABLE app_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  v INTEGER DEFAULT 1,                    -- Schema version
  type TEXT NOT NULL,                     -- Event category
  name TEXT NOT NULL,                     -- Specific event name
  message TEXT NOT NULL,                  -- Human-readable message
  severity TEXT DEFAULT 'info',           -- info|success|warning|error
  phase TEXT,                             -- For job_update: started|progress|succeeded|failed
  workspace_id UUID NOT NULL,             -- Required workspace scope
  basket_id UUID,                         -- Optional basket scope
  entity_id UUID,                         -- Optional entity reference
  correlation_id TEXT,                    -- Request tracking
  dedupe_key TEXT,                        -- Deduplication
  ttl_ms INTEGER,                         -- Time-to-live hint
  payload JSONB,                          -- Additional data
  created_at TIMESTAMPTZ DEFAULT now()
);
```

## Event Types

| Type              | Purpose                          | Example Names                    |
|-------------------|----------------------------------|----------------------------------|
| `job_update`      | Long-running job progress        | `anchor.seed`, `asset.classify`  |
| `system_alert`    | System-wide notifications        | `maintenance`, `quota_warning`   |
| `action_result`   | Immediate action feedback        | `block.create`, `asset.upload`   |
| `collab_activity` | Multi-user collaboration events  | `user.joined`, `edit.conflict`   |
| `validation`      | Data validation results          | `schema.validate`, `ref.check`   |

## EventService API

Located in `*/api/src/services/events.py`:

```python
from services.events import EventService

# Generic event
EventService.emit_app_event(
    workspace_id=workspace_id,
    type="job_update",
    name="anchor.seed",
    message="Generating anchor blocks...",
    phase="started",
    basket_id=basket_id,
    correlation_id=request_id
)

# Convenience methods for job lifecycle
EventService.emit_job_started(workspace_id, job_id, "anchor.seed", "Starting anchor seeding", basket_id)
EventService.emit_job_succeeded(workspace_id, job_id, "anchor.seed", "Anchor blocks created", basket_id)
EventService.emit_job_failed(workspace_id, job_id, "anchor.seed", "Anchor seeding failed", basket_id, error=str(e))
```

## Frontend Subscription

```typescript
import { createClient } from '@/lib/supabase/client'

const supabase = createClient()

supabase
  .channel('app-events')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'app_events',
      filter: `workspace_id=eq.${workspaceId}`
    },
    (payload) => {
      const event = payload.new
      // Handle event based on type/name
    }
  )
  .subscribe()
```

## Deprecated Systems (Removed)

The following systems were removed in November 2024:

| System           | Issue                                    | Replacement         |
|------------------|------------------------------------------|---------------------|
| `event_bus.py`   | LISTEN/NOTIFY - missing database trigger | `app_events`        |
| `events` table   | Legacy table, no realtime integration    | `app_events`        |
| `events_consumer`| Orphaned code, never invoked             | Realtime subscriptions |
| `EventRepository`| Wrote to legacy `events` table           | `EventService`      |

## Related: timeline_events (Audit History)

**Important**: `timeline_events` is a separate concern from `app_events`.

| Aspect          | `app_events`                     | `timeline_events`              |
|-----------------|----------------------------------|--------------------------------|
| Purpose         | Realtime notifications           | Audit history / timeline view  |
| Consumption     | Frontend via Supabase Realtime   | Frontend queries, audit logs   |
| Retention       | Short-lived (TTL-based cleanup)  | Long-term persistence          |
| Schema          | Notification-oriented            | Activity-oriented              |

`timeline_events` records what happened over time (history display), while `app_events` pushes immediate notifications to active users.

## Best Practices

1. **Always include `workspace_id`** - Required for security scoping
2. **Use `correlation_id`** - Links events to originating requests
3. **Use `dedupe_key`** for job events - Prevents duplicate notifications
4. **Keep messages human-readable** - They may be shown in toasts
5. **Use appropriate severity** - Drives UI treatment (color, icon, etc.)
6. **Include relevant IDs in payload** - Enables navigation/deep linking
