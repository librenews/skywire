# Skywire Deployment Walkthrough

Congratulations! You have successfully deployed **Skywire**, your robust Bluesky firehose ingestion service.

## 🏗️ Architecture

Your service is running on a single VPS with a self-contained architecture:

-   **Docker Compose**: Orchestrates the application and database containers.
-   **Skywire App**: Elixir/Phoenix service running in a Docker container.
    -   **Connection**: Persistent WebSocket to `wss://bsky.network`.
    -   **Processor**: Buffers and batches events.
    -   **Repo**: Stores events in Postgres.
-   **Postgres**: Running in a sidecar container (`db`), managed by Docker.
-   **Caddy**: Host-level reverse proxy handling automatic HTTPS/SSL and forwarding traffic to the app.

## 🚀 Deployment Status

-   **URL**: `https://skywire.social`
-   **Health Check**: `https://skywire.social/api/health`
-   **Link Stream**: `wss://skywire.social/socket/websocket?vsn=2.0.0` (Channel: `link_events`)
-   **SSL**: Automatically managed by Let's Encrypt via Caddy.
-   **Database**: Local persistent volume `postgres_data`.

## 🛠️ Operational Commands

### SSH into Server
```bash
ssh root@skywire.social
cd /opt/skywire
```

### View Logs
Check the application logs (including firehose ingestion status):
```bash
docker compose logs -f --tail=100 app
```

### Run Database Migrations
If you deploy new code with schema changes:
```bash
docker compose run --rm app /app/bin/migrate
```

### Generate API Token
To create a token for a new consumer:
```bash
docker compose exec app /app/bin/skywire eval 'Skywire.Release.gen_token("Consumer Name")'
```

### Update Application
When you push changes to GitHub:
```bash
git pull origin main
docker compose up -d --build
docker compose run --rm app /app/bin/migrate
```

## 🐛 Troubleshooting History

We solved several key issues during deployment:
1.  **DigitalOcean App Platform**: Moved away from it due to variable expansion issues (`${db.DATABASE_URL}`) and firewall complexity.
2.  **Failed Build**: Fixed `checksum` error by removing `mix.lock` from `.dockerignore`.
3.  **Crash Loop**: Fixed `CaseClauseError` in `Connection.ex` caused by unhandled 3-tuple return from `CBOR.decode`.
4.  **Migration Failure**: Switched to `docker compose run --rm` to run migrations reliably even when the app container is failing.

Your service is now robust and ready to ingest the firehose! 🌪️

## 4. Semantic Search & Embeddings

Skywire now includes a semantic search engine powered by `Bumblebee` (Elixir's HuggingFace integration) and `pgvector`.

### Architecture
- **Model**: `sentence-transformers/all-MiniLM-L6-v2` (runs locally on CPU).
- **Storage**: `vector(384)` column in PostgreSQL with HNSW index.
- **Ingestion**: 100% of incoming posts are embedded in real-time.
- **Serving**: Dual-process architecture:
    - `EmbeddingServing.Ingest`: High-throughput batch processing for firehose.
    - `EmbeddingServing.API`: Dedicated low-latency process for user queries.

### API Usage

**1. Search for Posts**
Find posts semantically similar to your query.
```bash
curl -X POST https://skywire.social/api/embeddings/search \
  -H "Authorization: Bearer <YOUR_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"query": "cats are cute", "limit": 5}'
```

**2. Generate Embedding (Debug)**
Get the raw vector for a piece of text.
```bash
curl -X POST https://skywire.social/api/embeddings/generate \
  -H "Authorization: Bearer <YOUR_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello world"}'
```

### Verification & Debugging

**Check Ingestion Status**
Use the built-in debug tool to see if embeddings are being created for new posts.
```bash
# Checks the last 100 posts
docker compose exec app /app/bin/skywire rpc "Skywire.Debug.check_recent_embeddings()"
```

**Output Meaning:**
- `found_with_embedding: 0` -> Ingestion is broken or backing up.
- .found_with_embedding: > 0` -> System is healthy and processing.

## 5. External Integrations (Webhooks)

Skywire can push real-time notifications to external apps (like a Rails backend) when posts match a subscription.

### Registration API
Your external app should call this to subscribe.

```bash
curl -X POST https://skywire.social/api/subscriptions \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "external_id": "rails-alert-101", 
    "query": "artificial intelligence news",
    "threshold": 0.82,
    "callback_url": "https://webhook.site/your-uuid"
  }'
```

### The Webhook Payload
When a match is found, Skywire POSTs this JSON to your `callback_url`:

```json
{
  "subscription_id": "rails-alert-101",
  "match_score": 0.89,
  "match_score": 0.89,
  "post": {
    "uri": "at://did:plc:123/app.bsky.feed.post/999",
    "text": "Huge breakthrough in AI today...",
    "author": "did:plc:123",
    "indexed_at": "2024-01-01T12:00:00Z",
    "raw_record": {
      "$type": "app.bsky.feed.post",
      "createdAt": "...",
      "text": "..."
    }
  }
}
```




### Verification
1.  Go to [Webhook.site](https://webhook.site) and get a unique URL.
2.  Register a subscription using the `curl` command above (replace URL).
3.  Wait for a matching post.
4.  Check Webhook.site to see the payload arrive!

### Management Commands

**Delete a Subscription**
```bash
curl -X DELETE https://skywire.social/api/subscriptions/rails-alert-101 \
  -H "Authorization: Bearer <TOKEN>"
```

**Nuclear Option (Delete ALL Subscriptions)**
If you want to clear the slate during development:
```bash
docker compose exec db psql -U postgres -d skywire_repo -c "TRUNCATE subscriptions;"
```

## 6. Real-time Preview (WebSocket)

Before saving a subscription, you can show the user a live preview of what matches their query.

### Connection
Connect to the socket using `phoenix.js` or any WebSocket client.
- **URL**: `wss://skywire.social/socket`
- **Topic**: `preview`

### Join Payload
Send this when joining the channel:
```json
{
  "query": "ruby on rails",
  "threshold": 0.8
}
```

### Events
When a post matches your ephemeral query, you receive a `new_match` event:
```json
{
  "matches": [
    {
      "score": 0.88,
      "post": {
        "text": "Just launched a new Rails app!",
        "author": "did:plc:...",
        "raw_record": { ... }
      }
    }
  ]
}
```
