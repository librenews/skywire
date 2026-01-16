# Architecture Decision: Redis Streams vs. WebSockets

## The Dilemma
We need to deliver a high volume of matches from Skywire (Ingestion) to Rails (Application).

## Option 1: Redis Streams (Recommended for Backend)
**Mechanism**: Skywire pushes matches to a persistent log (`key: skywire:matches`). Rails workers "pull" chunks of data, process them, and acknowledge (`ACK`) completion.

| Pro | Con |
| :--- | :--- |
| **Reliability** | **Zero Data Loss**. If Rails goes down, the stream persists. When Rails comes back, it picks up exactly where it left off. | **Connectivity** | Requires direct access to the Redis port. If Rails is on a different server, you need a secure tunnel (VPN/Stunnel) or public Redis (risky). |
| **Scalability** | **Consumer Groups**. You can spin up 10 Rails workers. Redis will load-balance the matches between them automatically. | | |
| **Backpressure** | Rails consumes at its own pace. If Skywire spikes to 1000 matches/sec, Rails won't crash; it just lags slightly behind. | | |

## Option 2: WebSocket Global Stream
**Mechanism**: Rails opens a long-lived HTTP connection (Upgrade: websocket) to Skywire. Skywire pushes JSON frames for every match.

| Pro | Con |
| :--- | :--- |
| **Simplicity** | Works over standard HTTP/HTTPS ports (easy for remote servers). | **Data Loss** | **Fire-and-forget**. If the connection drops for 1 second, you lose 1 second of matches. No built-in replay. |
| **Push** | Instant delivery (sub-millisecond latency). | **No Load Balancing** | Hard to distribute. If you have 2 Rails workers, do they both connect? Then you process every match twice. |

## Recommendation

**Use Redis Streams.**

For a "Social RSS Reader" where users subscribe to topics, missing a post because of a deployment restart or network blip is unacceptable. Redis Streams provides the "Inbox" guarantees you need.

### Deployment Note
To make this work, the Rails app must be able to reach the Skywire Redis.
1.  **Same Server (Docker)**: Use the internal docker network (`REDIS_URL=redis://skywire_redis:6379`).
2.  **Different Servers**: You will need to expose Redis securely or use a managed Redis (AWS/DigitalOcean/Upstash) that both apps connect to.
