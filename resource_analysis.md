# Resource Analysis: Full Stack on 16GB RAM

## The Components

1.  **OpenSearch (Skywire)**: **8GB Heap**. This is the specialized "heavy lifter". It needs this for the vector index.
2.  **Skywire (Elixir)**: **~500MB - 1GB**. Very efficient.
3.  **Redis (Shared)**: **~500MB**. Shared between Skywire and Rails (Sidekiq/Cache).
4.  **Postgres (Rails DB)**: **~1GB - 2GB**. Dependent on dataset size, but for a startup social app, 1GB shared buffer is plenty to start.
5.  **Rails App (Puma)**: **~500MB - 1GB**. Ruby is memory hungry, but manageable.
6.  **Rails Worker (Sidekiq)**: **~500MB**.

## The Math

| Component | Estimate (Conservative) | Estimate (Lean) |
| :--- | :--- | :--- |
| OpenSearch | 8 GB | 6 GB (If tuned down) |
| Skywire | 1 GB | 0.5 GB |
| Postgres | 2 GB | 1 GB |
| Rails (Web+Worker) | 1.5 GB | 1 GB |
| Redis | 0.5 GB | 0.2 GB |
| **System Overhead** | 2 GB | 1 GB |
| **TOTAL** | **15.0 GB** | **9.7 GB** |

## Conclusion

**It fits, but it's tight.**

You have **16GB** total.
- **Scenario A (Comfortable)**: You tune OpenSearch down slightly to **6GB Heap**. This leaves ~10GB for everything else, which is plenty of breathing room for Rails + Postgres.
- **Scenario B (Max Performance)**: You keep OpenSearch at **8GB**. You have ~6-7GB left for the OS + Rails + Postgres. This is valid, but if Postgres needs to do a heavy complex query, you might hit swap.

## Recommendation

**Start with Single Server.**

1.  **Cost Effective**: You pay for one VPS.
2.  **Simplicity**: No networking latency communicating between apps. Docker networking "just works".
3.  **Optimization**: **Lower OpenSearch to 6GB**. 6GB is widely considered robust for <10 million vectors. It frees up 2GB for your Rails app, making the whole system stable.

If you grow to millions of users, you simply migrate Rails+Postgres to a separate server later.
