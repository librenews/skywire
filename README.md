# Skywire ⚡️

**Skywire** is a high-throughput, real-time firehose ingestion and semantic search engine for the Bluesky/AT Protocol network.

It consumes the entire network stream (~50-100 posts/sec), generates semantic embeddings in real-time using **Bumblebee/EXLA** (local GPU inference with BAAI/bge-large-en-v1.5), and indexes them into **OpenSearch** for instant vector similarity search and "percolation" (reverse search) alerting.

## 🏗️ Architecture

Skywire runs as a lean, containerized microservice stack:

1.  **Skywire App (Elixir/Phoenix):**
    -   Connects to Bluesky Jetstream (`wss://jetstream1.us-east.bsky.network`).
    -   Filters & batches events.
    -   Generates embeddings via **Bumblebee/EXLA** (BAAI/bge-large-en-v1.5) on local GPU.
2.  **OpenSearch (NoSQL Vector Database):**
    -   Stores processed events.
    -   Performs K-NN (Vector) search.
    -   **Percolator:** Matches incoming posts against registered user subscriptions in real-time.
3.  **Redis:**
    -   Deduplication cache.
    -   **Output Stream:** Pushes matched events to `skywire:matches` for downstream consumers (e.g., Rails App).

> **Note:** This project uses local GPU inference via Bumblebee/EXLA for embedding generation. The Docker image is based on NVIDIA CUDA for GPU acceleration.

## 🚀 Deployment

The recommended deployment is via **Docker Compose** on a VPS (e.g., DigitalOcean, Hetzner).

**Requirements:**
-   **RAM:** 8GB Minimum (16GB Recommended for OpenSearch Performance).
-   **CPU:** 2+ vCPUs.
-   **Storage:** 50GB+ SSD.

### 1. Configure Environment
Enable the necessary variables in `.env`:
```bash
# ML Model (Optional, defaults to BAAI/bge-large-en-v1.5)
ML_MODEL_ID=BAAI/bge-large-en-v1.5
XLA_TARGET=cuda120  # or 'host' for CPU-only

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

## Local Development (Hybrid)

You can run the full stack locally (without a GPU) using the provided override file.
This will run the Main App using CPU for inference (slower but functional) and the Rails App on port 3001.

```bash
# Start everything locally (CPU Mode is now default!)
docker compose up -d --build
```

- **Firehose (App)**: `http://localhost:4000`
- **Track (Web)**: `http://localhost:3001`
- **Postgres**: Exposed on `5432`
- **Redis**: Exposed on `6379`

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
