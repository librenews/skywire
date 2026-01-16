# Deploying Rails with Kamal (Split Stack)

Skywire is designed to run on a dedicated "Backend" server, while your Rails application runs on a separate "frontend" server (or cluster) managed by [Kamal](https://kamal-deploy.org/).

## Architecture

*   **Server A (Skywire)**: Hosts OpenSearch, Skywire, and Redis.
*   **Server B (Rails)**: Hosts the Rails app, Sidekiq, and Postgres.

## Integration Point: Redis

The Rails application consumes matches from Skywire via **Redis Streams**.

### 1. Skywire Configuration (Server A)
Ensure `docker-compose.yml` exposes Redis with a password:
```yaml
  redis:
    command: redis-server --requirepass "${REDIS_PASSWORD}"
    ports:
      - "6379:6379"
```

### 2. Rails Configuration (Server B / Kamal)

In your Rails `deploy.yml` (Kamal config), you must set the `REDIS_URL` to point to Server A.

```yaml
# deploy.yml
env:
  secret:
    - REDIS_URL
```

In your `.env` (or whatever secrets manager you use for Kamal):

```bash
# redis://:PASSWORD@HOST:PORT/DB
REDIS_URL=redis://:YOUR_STRONG_PASSWORD@<IP_OF_SERVER_A>:6379/1
```

> [!IMPORTANT]
> Since Redis is exposed on a public port (or shared private network), ensure you have a **STRONG PASSWORD** set in `.env` on Server A.
