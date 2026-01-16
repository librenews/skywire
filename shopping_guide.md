# Server Shopping Guide (Minimum with Breathing Room)

To run the **Full Stack** (Skywire + Rails + Postgres) AND **Local AI** (BGE-Large), look for these specs.

## The "Comfortable Minimum"

| Component | Specification | Why? |
| :--- | :--- | :--- |
| **RAM** | **32 GB** | OpenSearch needs 16GB. Rails/Postgres need ~8GB. Leaves 8GB buffer. |
| **GPU** | **NVIDIA 8GB VRAM** | `bge-large` needs ~2-4GB VRAM. 8GB allows batching & future proofing. Look for: RTX 3070, 4060, A2000, A4000. |
| **Disk** | **1 TB NVMe** | 500GB fills up in ~10 days. 1TB gives you ~3-4 weeks of retention. |
| **CPU** | **4+ vCPUs** | Embedding work is on GPU. 4 cores is plenty for Rails/HTTP. |

## Why not lower?
- **< 32GB RAM**: You risk "Out of Memory" crashes when Postgres or Rails spikes.
- **< 8GB VRAM**: You can run the model, but might struggle with large batch sizes or concurrent requests.
- **< 1 TB Disk**: You will constantly be managing/deleting data to free up space.

## Recommended Strategy
This spec allows you to use the **Monorepo Strategy** (Everything on one box) with **Local AI**, keeping costs fixed and performance high.
