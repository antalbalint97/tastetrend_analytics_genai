# AWS Cost Estimate — TasteTrend GenAI PoC

## Assumptions

- **Region:** eu-central-1 (Frankfurt)
- **PoC usage:** 1–2 developers, ~50 queries/day during active development, data re-indexed weekly
- **MVP scale (100 DAU):** ~100 daily active users, ~10 queries per user/day = ~1,000 queries/day (~30,000/month)
- **Pricing as of 2024-Q4** (AWS public pricing; actual costs may vary)

---

## Monthly Cost Breakdown

| Service | Configuration (PoC) | Est. Monthly Cost (PoC) | Configuration (100 DAU MVP) | Est. Monthly Cost (MVP) |
|---|---|---|---|---|
| **OpenSearch** | `t3.small.search` × 1 node, 20 GiB gp3 EBS | **$27.00** | `m5.large.search` × 2 nodes (Multi-AZ), 50 GiB gp3 | **$220.00** |
| **Lambda — ETL** | ~4 invocations/month, 3008 MB, 60s avg duration | **$0.02** | ~30 invocations/month (scheduled) | **$0.15** |
| **Lambda — Embedding** | ~4 invocations/month, 3008 MB, 300s avg duration | **$0.06** | ~30 invocations/month | **$0.50** |
| **Lambda — Search** | ~1,500 invocations/month, 512 MB, 2s avg duration | **$0.04** | ~30,000 invocations/month | **$0.80** |
| **Lambda — Proxy** | ~1,500 invocations/month, 128 MB, 3s avg duration | **$0.02** | ~30,000 invocations/month | **$0.50** |
| **Bedrock — Claude 3 Haiku** | ~1,500 calls/month, ~500 input + 300 output tokens/call | **$0.75** | ~30,000 calls/month | **$15.00** |
| **Bedrock — Titan Embed v2** | ~2,000 embeddings/month (re-index) + ~1,500 query embeds | **$0.04** | ~30,000 query embeds + 5,000 index embeds/month | **$0.35** |
| **API Gateway (HTTP)** | ~1,500 requests/month | **$0.002** | ~30,000 requests/month | **$0.03** |
| **S3** | 3 buckets, <1 GiB total, ~5,000 requests/month | **$0.10** | 3 buckets, ~5 GiB, ~50,000 requests/month | **$0.50** |
| **KMS** | 1 CMK + ~3,000 API calls/month | **$1.03** | 1 CMK + ~60,000 API calls/month | **$1.18** |
| **CloudWatch Logs** | ~500 MB ingested/month | **$0.25** | ~5 GiB ingested/month | **$2.50** |
| **Data Transfer** | Minimal (same-region) | **$0.00** | ~10 GiB out/month | **$0.90** |
| | | | | |
| **Total (estimated)** | | **~$29** | | **~$242** |

---

## Cost Notes

### OpenSearch (largest cost driver)

- The PoC uses a single `t3.small.search` node ($0.036/hr × 730 hrs ≈ $26.28).
- No reserved instances — on-demand pricing only.
- For MVP, a Multi-AZ deployment with `m5.large.search` ($0.146/hr × 2 nodes) is recommended for availability.
- **Cost optimisation:** Consider reserved instances (1-year commitment) for ~40% savings at production scale.

### Bedrock — Claude 3 Haiku

- Input: $0.00025 / 1K tokens → ~500 tokens/query → $0.000125/query
- Output: $0.00125 / 1K tokens → ~300 tokens/query → $0.000375/query
- Total per query: ~$0.0005
- **1,500 queries/month (PoC):** ~$0.75
- **30,000 queries/month (MVP):** ~$15.00
- If upgrading to **Sonnet** ($0.003/$0.015 per 1K tokens), expect ~12× the Haiku cost → ~$180/month at MVP scale.

### Bedrock — Titan Embed Text v2

- $0.0001 / 1K tokens → ~100 tokens per review or query
- Extremely cheap: even at 30K embeddings/month → $0.30

### Lambda

- Lambda is effectively free at PoC scale.
- At MVP scale (30K invocations/month), the cost is dominated by the free tier (400,000 GB-s/month).
- The ETL and Embedding Lambdas use the `AWSSDKPandas` layer — no additional cost.

### API Gateway

- HTTP API pricing: $1.00 per million requests.
- At 30K requests/month, cost is negligible ($0.03).

### KMS

- $1.00/month per customer-managed key (CMK).
- API calls: $0.03 per 10,000 requests.

---

## Cost Optimisation Opportunities (MVP → Production)

| Opportunity | Estimated Savings | Effort |
|---|---|---|
| OpenSearch Reserved Instances (1-year) | ~40% on OpenSearch | Low (commitment) |
| Provisioned Throughput for Bedrock (if available) | Up to 30% on model calls | Medium |
| S3 Intelligent-Tiering for processed data | Negligible at current scale | Low |
| Lambda ARM64 (Graviton) architecture | ~20% on Lambda compute | Low (rebuild ZIPs) |
| Move frontend to CloudFront + S3 (eliminate Vercel) | Saves Vercel Pro costs | Medium |
