# Bluesky Firehose Elixir Ingestion Service

This document is **explicit instructions** for a coding agent to implement a **simple, robust, single-deployment Elixir service** that consumes the Bluesky firehose once and makes it safely consumable by many downstream apps.

The design goal is **boringly reliable infrastructure**, not experimentation.

---

## 0. Core Principles (DO NOT SKIP)

1. **One ingestion service, many consumers**
   - This app is the *only* thing that talks to Bluesky’s firehose
   - All other apps consume *from this app*, never from Bluesky directly

2. **Durable log first, streaming second**
   - Every event is written to a database
   - Consumers read from the database or a filtered API

3. **At-least-once delivery**
   - Cursor is only advanced *after* persistence succeeds

4. **Single instance by default**
   - Firehose is not horizontally scalable without coordination
   - HA is possible later via leader election

---

## 1. What This Service Does

- Connects to the Bluesky firehose (`com.atproto.sync.subscribeRepos`)
- Automatically reconnects on failure
- Resumes from the last processed sequence number
- Stores all events in a durable database
- Exposes a secure API for other apps to consume filtered subsets

This service **does not**:
- Render UI
- Apply product logic
- Filter aggressively during ingestion

---

## 2. Tech Stack (MANDATORY)

- **Language:** Elixir
- **Framework:** Phoenix (API-only)
- **WebSocket:** WebSockex *or* Mint.WebSocket
- **Database:** PostgreSQL
- **Deployment:** single container or VM

---

## 3. Bluesky Firehose Basics (Context)

Endpoint:
```
wss://bsky.network/xrpc/com.atproto.sync.subscribeRepos
```

Supports:
- WebSocket connection
- `since` query param for cursor replay
- Monotonically increasing `seq` value

The `seq` value is the **only cursor you need**.

---

## 4. Application Structure

### Supervision Tree

```
Application
├── Registry
├── CursorStore
├── Firehose.Connection
├── Firehose.Processor
└── Firehose.API (Phoenix Endpoint)
```

**Important:**
- The WebSocket process MUST be supervised
- Crashes are expected and healthy

---

## 5. Database Schema

### Cursor Table

Used to store the last successfully processed sequence.

```sql
CREATE TABLE firehose_cursor (
  id boolean PRIMARY KEY DEFAULT true,
  last_seq bigint NOT NULL
);

INSERT INTO firehose_cursor (id, last_seq)
VALUES (true, 0)
ON CONFLICT DO NOTHING;
```

There must be **exactly one row**.

---

### Event Log Table

```sql
CREATE TABLE firehose_events (
  seq bigint PRIMARY KEY,
  repo text NOT NULL,
  event_type text NOT NULL,
  collection text,
  record jsonb,
  indexed_at timestamptz DEFAULT now()
);

CREATE INDEX ON firehose_events (event_type);
CREATE INDEX ON firehose_events (collection);
CREATE INDEX ON firehose_events (repo);
```

**DO NOT** over-normalize at this stage.

---

## 6. CursorStore Module

### Responsibilities

- Read last cursor on startup
- Update cursor only after DB transaction commits

### Required Behavior

- Must be synchronous
- Must be crash-safe

### Pseudocode

```elixir
get_cursor() :: integer
set_cursor(seq :: integer) :: :ok
```

---

## 7. Firehose WebSocket Client

### Connection Rules

- Read cursor from `CursorStore` on init
- Append `?since=<cursor>` to URL
- On disconnect, crash the process
- Let supervisor restart it

### Why crash?

OTP supervision gives:
- exponential backoff
- clean state reset
- simpler logic

---

### Message Handling Flow

For each incoming message:

1. Decode CBOR
2. Extract `seq`
3. Persist event(s) inside a DB transaction
4. Update cursor
5. Acknowledge internally

**If any step fails → crash**

---

## 8. Event Processing Rules

- Accept **all event types** initially
- Store raw records as JSONB
- Do not apply business filtering during ingestion

Reason:
- You will want events later that you thought you didn’t need

---

## 9. Phoenix API for Consumers

### Authentication

- Token-based auth
- One token per consumer app
- Read-only access

Example header:
```
Authorization: Bearer <token>
```

---

### Core Endpoints

#### Fetch Events

```
GET /events
```

Query params:
- `since` (required)
- `event_type` (optional)
- `collection` (optional)
- `repo` (optional)
- `limit` (default 100, max 1000)

Response:
- ordered list of events
- highest `seq` included

---

#### Health Check

```
GET /health
```

Returns:
- last processed seq
- lag vs current time

Used by deployment platform.

---

## 10. Security Model

- Tokens stored hashed in DB
- Tokens scoped to allowed filters
- Rate limiting per token

**No OAuth required.**

This is infra-to-infra communication.

---

## 11. Deployment Instructions

### Environment Variables

```
DATABASE_URL=
SECRET_KEY_BASE=
API_TOKEN_SALT=
```

---

### Runtime Requirements

- Single running instance
- Automatic restarts enabled
- Persistent database

---

## 12. High-Volume Throughput Requirements

This service MUST be capable of handling **thousands of firehose events per second** during peak periods.

### Design Assumptions

- Firehose traffic is **bursty**, not constant
- Events are small (likes, follows, posts)
- Temporary lag is acceptable
- Replay from cursor is always possible

---

### Mandatory Performance Techniques

1. **Batching is required**
   - Events MUST be written to the database in batches
   - Individual per-event inserts are NOT allowed

2. **Batch size rules**
   - Flush batch when:
     - 200–1000 events accumulated OR
     - 50–100ms elapsed (whichever happens first)

3. **Cursor advancement rules**
   - Cursor MUST be updated only after a successful batch commit
   - Cursor updates inside the same DB transaction are preferred

4. **Backpressure behavior**
   - If database writes slow down:
     - In-memory buffer grows
     - WebSocket reader applies backpressure
   - If buffer reaches max capacity:
     - The process MUST crash intentionally
     - Supervisor restarts it
     - Replay resumes from last persisted cursor

Crashing under sustained overload is **correct behavior**.

---

### Memory Constraints

- Only milliseconds-to-seconds of events may be buffered in memory
- No unbounded queues
- No long-lived in-memory event storage

---

### Database Write Expectations

PostgreSQL configuration MUST support:

- Batched inserts
- Async commit (acceptable)
- Sustained high write throughput

Postgres is treated as an **append-only log**, not an OLTP system.

---

## 13. Data Retention & Trimming Policy

This service is **NOT** responsible for long-term historical storage.

### Retention Rules

- Firehose events MUST be retained for only **several days** (configurable)
- Downstream applications are responsible for persisting any data they need

### Trimming Strategy

- Periodic deletion of old rows is REQUIRED
- Trimming MAY be done via:
  - scheduled job
  - time-based partition dropping

### Example Policy

- Retain last 3–7 days of data
- Delete events where:
  - `indexed_at < now() - interval '7 days'`

---

### Why This Is Required

- Prevent unbounded disk growth
- Keep database fast and predictable
- Treat this service as a **transient replication buffer**, not an archive

---

## 14. Failure Scenarios (EXPECTED)

| Failure | Result |
|------|------|
| WebSocket disconnect | Process restarts |
| App crash | Cursor resumes |
| DB restart | Ingestion pauses |
| Deployment | No data loss |

------|------|
| WebSocket disconnect | Process restarts |
| App crash | Cursor resumes |
| DB restart | Ingestion pauses |
| Deployment | No data loss |

---

## 13. Things NOT To Do

- Do NOT process business logic during ingestion
- Do NOT skip storing raw events
- Do NOT acknowledge cursor before persistence
- Do NOT run multiple ingestion nodes without coordination

---

## 15. Future Extensions (OUT OF SCOPE)

- Kafka / NATS fanout
- Leader election
- Secondary indexes
- Real-time push subscriptions

These can all be built **on top of the event log**.

---

## 15. Final Mental Model

> This app is a **Bluesky replication service**, not a client.

Treat it like Postgres replication or an append-only log.

Everything else becomes simpler once this is correct.