# Server Feasibility Matrix

| Feature | **Option A (The Beast)** | **Option B (The Value)** | **Option C (Low Spec)** |
| :--- | :--- | :--- | :--- |
| **Specs** | 64GB RAM / 20GB VRAM / 2TB | 32GB RAM / 20GB VRAM / 500GB | 8GB RAM / 2GB VRAM / 50GB |
| **OpenSearch** | ✅ Amazing (30GB Heap) | ✅ Good (16GB Heap) | ❌ **Crash Risk** (4GB Heap max) |
| **AI Model** | ✅ **Large Model** (Local) | ✅ **Large Model** (Local) | ❌ **Small Model Only** |
| **Retention** | ✅ Months (100M+ vectors) | ⚠️ ~1 Week | ❌ **< 2 Days** |
| **Full Stack?** | ✅ Yes (Monorepo) | ✅ Yes (Monorepo) | ❌ **No**. Must split stack. |
| **Verdict** | **Recommended** | **Viable MVP** | **Not Production Ready** |

## Analysis of Option C (8GB / 50GB)

This server is **too small** for the full stack.

1.  **RAM (8GB)**: OpenSearch needs ~4-6GB minimum to be stable. That leaves 2GB for the OS, Rails, Skywire, and Redis. The system will likely OOM (Out of Memory) and crash constantly.
2.  **Disk (50GB)**: Even with the small model, you are ingesting gigabytes per day. This drive will fill up in 48 hours.
3.  **VRAM (2GB)**: You cannot run the High Quality (Large) model. You are forced to use the Small model.

**Conclusion**: Do not use Option C for the full stack. It is only suitable if you are splitting the stack into microservices across many servers.
