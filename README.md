# Skywire ⚡️

**Skywire** is a high-throughput, real-time firehose ingestion and semantic search engine for the Bluesky/AT Protocol network.

It consumes the entire network stream (~50-100 posts/sec), generates semantic embeddings in real-time using **Cloudflare Workers AI**, and indexes them into **OpenSearch** for instant vector similarity search and "percolation" (reverse search) alerting.

## 🏗️ Architecture

Skywire runs as a lean, containerized microservice stack:

1.  **Skywire App (Elixir/Phoenix):**
    -   Connects to Bluesky Jetstream (`wss://jetstream1.us-east.bsky.network`).
    -   Filters & batches events.
    -   Generates embeddings via **Cloudflare Workers AI** (BGE-M3/MiniLM).
2.  **OpenSearch (NoSQL Vector Database):**
    -   Stores processed events.
    -   Performs K-NN (Vector) search.
    -   **Percolator:** Matches incoming posts against registered user subscriptions in real-time.
3.  **Redis:**
    -   Deduplication cache.
    -   **Output Stream:** Pushes matched events to `skywire:matches` for downstream consumers (e.g., Rails App).

> **Note:** This project uses a "Lightweight" architecture. It has **zero** local ML dependencies (no Python, no Bumblebee, no Torch) to keep the Docker image small (<200MB) and RAM usage low.

## 🚀 Deployment

The recommended deployment is via **Docker Compose** on a VPS (e.g., DigitalOcean, Hetzner).

**Requirements:**
-   **RAM:** 8GB Minimum (16GB Recommended for OpenSearch Performance).
-   **CPU:** 2+ vCPUs.
-   **Storage:** 50GB+ SSD.

### 1. Configure Environment
Enable the necessary variables in `.env`:
```bash
# Cloudflare AI (Required for Embeddings)
CLOUDFLARE_ACCOUNT_ID=...
CLOUDFLARE_API_TOKEN=...
HF_TOKEN=...

# Persistence
EVENT_RETENTION_DAYS=3

# External Access
PHX_HOST=your-domain.com
SECRET_KEY_BASE=...
```

### 2. Launch
```bash
docker compose up -d
```
*Note: Ensure `opensearch` container gets sufficient memory (configured for 2GB Heap in `docker-compose.yml`).*

## 🔌 API & Integration

Skywire is designed to be a "Headless" ingestion engine. Your user-facing application (Rails, Node, etc.) consumes its output.

### 1. Subscription Management (REST)
Register a new "Alert" for a user.
`POST /api/subscriptions`
```json
{
  "external_id": "user_id_123",
  "query": "artificial intelligence breakthroughs",
  "threshold": 0.8
}
```

### 2. Consuming Matches (Redis Stream)
Listen to the `skywire:matches` Redis stream. Each message contains the post and the `external_id` it matched.

### 3. Real-time Preview (WebSocket)
Connect to `wss://your-domain.com/socket` to stream ephemeral previews for UI wizards.

*See `api.md` for full API documentation.*

## 🛠️ Operations

**View Logs:**
```bash
docker compose logs -f app
```

**Check Health:**
```bash
curl https://localhost/api/health
```

**Manual Embedding Test:**
```bash
docker compose exec app /app/bin/skywire rpc "Skywire.Debug.check_vector_magnitude()"
```

## 📜 License
MIT
