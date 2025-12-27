# Skywire - Bluesky Firehose Ingestion Service

A reliable Elixir service that ingests the Bluesky firehose and makes it safely consumable by downstream applications.

## Architecture

- **Single ingestion point**: One service talks to Bluesky, many apps consume from this service
- **Durable log first**: All events stored in PostgreSQL before acknowledgment
- **High throughput**: Batched writes handle thousands of events/second
- **Crash-safe**: Cursor-based resumption ensures no data loss

## Quick Start

### Prerequisites

- Elixir 1.14+
- PostgreSQL
- Mix

### Setup

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Generate an API token
mix skywire.gen_token "My App"

# Start the server
mix phx.server
```

The service will:
1. Connect to Bluesky firehose
2. Start ingesting events
3. Expose API endpoints on `http://localhost:4000`

## Deployment

### Quick Deploy to Fly.io

```bash
# Install Fly CLI
brew install flyctl

# Login and create Postgres
fly auth login
fly postgres create --name skywire-db --region iad

# Deploy from your repo
fly launch --no-deploy
fly postgres attach skywire-db
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly deploy
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete deployment guides for Fly.io, Render, and Railway.

## API Endpoints

### Health Check (Public)

```bash
GET /api/health
```

Returns cursor position and processing lag.

### Query Events (Authenticated)

```bash
GET /api/events?since=0&limit=100
Authorization: Bearer YOUR_TOKEN
```

Query parameters:
- `since` (required): Start from this sequence number
- `limit` (optional): Max events to return (default: 100, max: 1000)
- `event_type` (optional): Filter by event type
- `collection` (optional): Filter by collection
- `repo` (optional): Filter by repo DID

## Configuration

### Environment Variables

```bash
DATABASE_URL=postgresql://user:pass@localhost/skywire_prod
SECRET_KEY_BASE=your_secret_key
PORT=4000
```

### Data Retention

Configure retention period in `config/runtime.exs`:

```elixir
config :skywire, event_retention_days: 7  # Default: 7 days
```

## Deployment

### VPS Deployment

1. Build release:
```bash
MIX_ENV=prod mix release
```

2. Set environment variables
3. Run migrations:
```bash
_build/prod/rel/skywire/bin/skywire eval "Skywire.Release.migrate"
```

4. Start service:
```bash
_build/prod/rel/skywire/bin/skywire start
```

### Systemd Service

Create `/etc/systemd/system/skywire.service`:

```ini
[Unit]
Description=Skywire Firehose Service
After=network.target postgresql.service

[Service]
Type=simple
User=skywire
WorkingDirectory=/opt/skywire
Environment=PORT=4000
Environment=DATABASE_URL=postgresql://...
Environment=SECRET_KEY_BASE=...
ExecStart=/opt/skywire/bin/skywire start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

## Token Management

Generate a new API token:

```bash
mix skywire.gen_token "Consumer App Name"
```

⚠️ Save the token immediately - it won't be shown again!

## Monitoring

- Health endpoint: `/api/health`
- LiveDashboard (dev): `http://localhost:4000/dev/dashboard`
- Logs: Standard output (JSON in production)

## Architecture Details

### Components

- **CursorStore**: Manages sequence cursor state
- **Connection**: WebSocket client to Bluesky firehose
- **Processor**: Batches events for efficient DB writes
- **DataTrimmer**: Daily cleanup of old events

### Failure Handling

| Failure | Behavior |
|---------|----------|
| WebSocket disconnect | Process restarts, resumes from cursor |
| Database unavailable | Ingestion pauses, retries |
| Buffer overflow | Process crashes, restarts from cursor |
| Deployment | No data loss, resumes from cursor |

## Performance

- **Throughput**: Handles 1000+ events/second
- **Batching**: Flushes every 500 events or 100ms
- **Backpressure**: Intentional crash if buffer exceeds 2000 events
- **Storage**: Append-only log, 3-7 day retention

## License

MIT
