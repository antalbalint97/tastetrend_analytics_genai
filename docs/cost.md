# AWS Cost Estimation — TasteTrend Analytics GenAI

> **Methodology:** Costs estimated using the AWS Pricing Calculator (EU Frankfurt / eu-central-1 region).  
> Workload estimate ID: `f4e9d7a8-03f5-40a4-bebb-bdcd7da2e94f`  
> Rates as of: March 2026, Before Discount.

---

## PoC Monthly Cost Breakdown

| Service | Configuration | Monthly Cost (USD) |
|---|---|---|
| Amazon OpenSearch Service | t3.small.search, 1 node, 744 hrs | $31.25 |
| AWS KMS | 1 CMK + 1,000 symmetric API calls | $1.00 |
| AWS Lambda | 500 requests × 8s × 128MB | $0.01 |
| Amazon S3 | 1 GB storage + 1,000 PUT + 5,000 GET | $0.03 |
| Amazon API Gateway | HTTP API, 500 requests | $0.00 |
| **AWS subtotal** | | **$32.29** |
| Amazon Bedrock (Claude 3 Haiku)* | 500K input tokens + 100K output tokens | $0.80 |
| Vercel (Frontend hosting) | Hobby plan | $0.00 |
| **Total PoC estimate** | | **~$33/month** |

*Bedrock is not available in the AWS Pricing Calculator. Manually calculated:
- Input: 500,000 tokens × $0.80/1M = **$0.40**
- Output: 100,000 tokens × $4.00/1M = **$0.40**
- **Bedrock total: ~$0.80/month** at PoC usage levels

---

## Key Cost Driver

**OpenSearch (t3.small.search) represents ~95% of total cost** at PoC scale.  
This is expected — a dedicated search cluster has a fixed hourly cost regardless of query volume.  
At PoC scale (< 100 queries/day), this is the main trade-off vs. a serverless alternative.

---

## Scaling to MVP: 100 Daily Active Users

Assumptions:
- 100 DAU × 5 queries/day = **~15,000 queries/month**
- Avg 1,500 input tokens + 300 output tokens per query
- OpenSearch scaled to `m5.large.search` (2 nodes, multi-AZ)

| Service | PoC Config | PoC Cost | MVP Config | MVP Est. Cost |
|---|---|---|---|---|
| OpenSearch | t3.small, 1 node | $31.25 | m5.large, 2 nodes (multi-AZ) | ~$280 |
| AWS Lambda | 500 req/month | $0.01 | 15,000 req/month | ~$0.50 |
| API Gateway | 500 req/month | $0.00 | 15,000 req/month | ~$0.02 |
| S3 | 1 GB | $0.03 | 10 GB | ~$0.25 |
| KMS | 1 CMK | $1.00 | 1 CMK | $1.00 |
| Bedrock (Haiku) | ~600K tokens | $0.80 | ~27M tokens | ~$25 |
| Cognito (Auth) | — | — | 100 MAU (free tier) | $0.00 |
| CloudWatch | Basic | ~$0 | Logs + Alarms | ~$5 |
| **Total** | | **~$33/month** | | **~$312/month** |

---

## Cost Optimization Opportunities

**Short term (PoC → MVP):**
- Replace OpenSearch `t3.small` with **OpenSearch Serverless** for infrequent workloads — pay per OCU-hour instead of always-on instance
- Use **Claude 3 Haiku** over Sonnet — 10× cheaper with acceptable quality for structured review queries (already implemented)
- Enable **Lambda reserved concurrency** to prevent runaway costs

**Medium term (MVP → Production):**
- Evaluate **Aurora pgvector** as OpenSearch replacement if query patterns are simple — significantly cheaper at scale
- Implement **response caching** at API Gateway level for repeated queries
- Use **Bedrock Provisioned Throughput** if query volume exceeds 1M tokens/month for predictable pricing

---

## AWS Free Tier Impact

The following services have free tier coverage that reduces PoC costs further:

| Service | Free Tier |
|---|---|
| AWS Lambda | 1M requests + 400,000 GB-seconds/month |
| Amazon API Gateway | 1M HTTP API calls/month (first 12 months) |
| Amazon S3 | 5 GB storage + 20,000 GET + 2,000 PUT (first 12 months) |

> At PoC usage levels, Lambda and API Gateway costs are effectively **$0.00** due to free tier coverage.  
> The real cost of running this PoC is the **OpenSearch instance + KMS key = ~$32.25/month**.
