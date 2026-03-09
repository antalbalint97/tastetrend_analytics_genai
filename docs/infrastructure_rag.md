# Infrastructure Decision Record – TasteTrend RAG (GenAI Proof of Concept)

**Purpose**  
Document architectural and infrastructure decisions for the **Retrieval-Augmented Generation (RAG)** pipeline developed for the TasteTrend AWS GenAI Proof of Concept (PoC).

**Goal**  
Demonstrate that restaurant review data can be semantically retrieved and used to generate grounded, factual responses through **Amazon Bedrock Agent** integrated with **Amazon OpenSearch** and a **Vercel-hosted frontend**.

---

## 1. Context and Objectives

This Proof of Concept focuses on validating the **end-to-end RAG pipeline** from data ingestion to a live, queryable frontend demo.  
The goal is not scalability or automation, but **accuracy, transparency, and speed of iteration**.

The system enables natural-language queries such as:  
_"Which location has the most complaints about waiting times?"_  
and returns evidence-based answers grounded in actual customer reviews, including the source reviews themselves.

---

## 2. Final Architecture

```
S3 (raw CSVs)
     ↓
ETL Lambda (tastetrend-poc-etl)
     ↓
S3 (processed parquet)
     ↓
Embedding Lambda (tastetrend-poc-embedding)
  → Bedrock Titan Embed Text v2 (1024D)
     ↓
Amazon OpenSearch (tastetrend-demo, t3.small.search)
     ↓ (KNN vector search)
Search Lambda (tastetrend-poc-search)  ← Bedrock Agent action group
     ↑
Bedrock Agent (IVEGCZX9LV, Claude 3 Haiku, live-haiku alias → Version 5)
     ↑
Proxy Lambda (tastetrend-proxy-lambda)
     ↑
API Gateway (HTTP API, bbtsnacxpf)
     ↑
Vercel Frontend (tastetrend-ai-demo.vercel.app)
  → Vercel serverless function (/api/query) proxies requests
```

| Component | Service | Config |
|-----------|---------|--------|
| Embedding model | Bedrock Titan Embed Text v2 | 1024D vectors |
| Vector store | OpenSearch managed domain | t3.small.search, eu-central-1 |
| Orchestration | Bedrock Agent | Claude 3 Haiku, Version 5 |
| Search action | Lambda (search_reviews) | KNN + location-aware filter |
| API proxy | Lambda + API Gateway | HTTP API, x-api-key auth |
| Frontend | Vercel + serverless function | Next.js/Vite, /api/query proxy |

---

## 3. Key Decisions

### 3.1 OpenSearch Managed Domain (not Serverless)
**Decision:** Use OpenSearch managed domain (`t3.small.search`) instead of OpenSearch Serverless.  
**Rationale:**
- Managed domain offers more predictable pricing for a persistent PoC.
- Serverless OCU minimum cost (~$700/month) is prohibitive for a PoC with low query volume.
- Terraform provider support is more mature for managed domains.  

**Trade-off:** Single-AZ, no replication — not suitable for production.  
**Mitigation (MVP):** Move to multi-AZ domain with replica shards and fine-grained access control.

---

### 3.2 Bedrock Agent over Direct Lambda RAG
**Decision:** Use Amazon Bedrock Agent with an action group instead of a direct Lambda RAG chain.  
**Rationale:**
- Bedrock Agent provides built-in orchestration, multi-turn conversation, and tool use without custom chaining code.
- Action group pattern cleanly separates retrieval (Search Lambda) from generation (Claude).
- Native AWS integration simplifies IAM and removes external dependencies.

**Trade-off:** Bedrock Agent adds ~2–3s orchestration overhead vs direct invocation.  
**Mitigation:** Acceptable for a PoC demo; for production, evaluate latency budget and consider direct RAG if needed.

---

### 3.3 Claude 3 Haiku over Sonnet
**Decision:** Use `anthropic.claude-3-haiku-20240307-v1:0` as the foundation model.  
**Rationale:**
- Claude 3.5 Sonnet is not directly available in `eu-central-1` — only via EU inference profile (`eu.anthropic...`), which did not propagate correctly through the Bedrock Agent runtime in testing.
- Haiku is available as a direct model ID in `eu-central-1` and works reliably.
- For structured review analytics queries, Haiku's output quality is indistinguishable from Sonnet at 10× lower cost.

**Trade-off:** Less capable on complex multi-step reasoning.  
**Mitigation:** The action group architecture offloads retrieval complexity to the Search Lambda, reducing reasoning requirements on the model.

---

### 3.4 Embedding Lambda over EC2 Batch Run
**Decision:** Use a Lambda function (`tastetrend-poc-embedding`) for embedding generation and OpenSearch indexing.  
**Rationale:**
- Lambda integrates cleanly into the existing IaC and deployment pipeline.
- No EC2 instance lifecycle to manage.
- Embedding run is a one-time setup operation — Lambda's execution time is sufficient.

**Trade-off:** Lambda 15-minute timeout limits very large batch sizes; 1660 reviews processed successfully within limits.  
**Mitigation (MVP):** For larger datasets, use Step Functions with batched Lambda invocations.

---

### 3.5 Proxy Lambda + API Gateway over Direct Bedrock Invocation
**Decision:** Frontend calls a Proxy Lambda via API Gateway, which invokes the Bedrock Agent.  
**Rationale:**
- Keeps AWS credentials server-side; frontend never handles IAM keys.
- API key authentication (`x-api-key` header, SHA-256 hashed) provides lightweight access control suitable for a PoC demo.
- Proxy Lambda handles streaming response parsing and returns a stable JSON contract to the frontend.

**Trade-off:** Extra hop adds ~50–100ms latency.  
**Mitigation:** Negligible compared to Bedrock Agent response time (~5–10s).

---

### 3.6 Vercel Frontend with Serverless Proxy
**Decision:** Host the frontend on Vercel with a `/api/query` serverless function proxying to API Gateway.  
**Rationale:**
- Vercel provides instant HTTPS deployment with zero infrastructure management.
- The serverless function keeps the `API_KEY` server-side (not exposed in browser bundle).
- Free tier sufficient for PoC demo traffic.

**Trade-off:** Adds another proxy hop (Browser → Vercel → API GW → Lambda → Bedrock).  
**Mitigation:** Total p50 latency is ~7–10s end-to-end, dominated by Bedrock Agent processing — the Vercel hop is negligible.

---

## 4. Data Workflow

1. Load dataset (`processed_final.parquet`) from S3.
2. ETL Lambda cleans and normalizes raw CSVs → processed parquet.
3. Embedding Lambda generates Titan embeddings in batches.
4. Documents bulk-indexed into OpenSearch (`reviews` index, KNN enabled).
5. Search Lambda performs KNN vector search with optional location filter.
6. Bedrock Agent orchestrates tool calls and generates grounded responses.
7. Proxy Lambda parses streaming response and returns structured JSON.

**Outcome:**
- 1,660 reviews indexed successfully (0 failures).
- Queries return semantically relevant results with source review attribution.
- Average end-to-end latency: ~7–10 seconds.

---

## 5. Security & IAM

| Role | Purpose | Key Permissions |
|------|----------|----------------|
| `tt-etl-lambda-role` | ETL processing | S3 read/write |
| `tt-embedding-lambda-role` | Embedding + indexing | S3 read, Bedrock invoke, OpenSearch write |
| `tt-search-lambda-role` | KNN search | OpenSearch read |
| `tt-bedrock-agent-role` | Agent orchestration | Lambda invoke, Bedrock model invoke |
| `tt-proxy-lambda-role` | API proxy | Bedrock Agent invoke |

**Security Controls:**
- Principle of least privilege applied to all roles.
- All S3 buckets: public access blocked, SSE-KMS encryption.
- API key authentication on the proxy endpoint (SHA-256 hashed, never stored in plaintext).
- Vercel serverless function keeps the API key server-side.
- *Next Step (MVP):* Replace API key auth with Cognito JWT, restrict OpenSearch to VPC.

---

## 6. Observability & Validation

**Logging:**
- All Lambda functions log to CloudWatch (`/aws/lambda/tastetrend-*`).
- Proxy Lambda logs query, latency, and result count per request.
- Bedrock Agent trace enabled (`enableTrace=True`) for action group debugging.

**Validation:**
- Smoke tested against all 12 example business queries from the SOW.
- Source reviews (`results[]`) returned and validated per response.
- Average latency: ~7,500ms (acceptable for PoC; target <3s for MVP).

---

## 7. Infrastructure as Code

**Terraform Modules**

| Module | Manages |
|--------|---------|
| `modules/opensearch` | OpenSearch domain, access policy |
| `modules/bedrock_agent` | Agent, alias, action group, Lambda permission |
| `modules/lambda/proxy` | Proxy Lambda (with `lifecycle ignore_changes` on env vars) |
| `modules/lambda/search` | Search Lambda |
| `modules/lambda/embedding` | Embedding Lambda |
| `modules/lambda/etl` | ETL Lambda |
| `modules/iam` | All roles and policies |
| `modules/api` | API Gateway HTTP API + integration |

**Notable IaC decision:**  
The proxy Lambda's `environment` block uses `lifecycle { ignore_changes = [environment] }` to prevent Terraform from overwriting manually managed env vars (`AGENT_ALIAS`, `API_KEY_HASH`) on each `terraform apply`.

---

## 8. Known Limitations (PoC Scope)

| Area | Limitation | MVP Fix |
|------|-----------|---------|
| Auth | Static API key | Cognito / JWT |
| OpenSearch | Single-AZ, no replicas | Multi-AZ domain |
| Terraform state | Local state file | S3 remote state + DynamoDB lock |
| Agent alias | Manually created in console | Terraform `aws_bedrockagent_agent_version` resource |
| Latency | ~7–10s p50 | Response streaming to frontend |
| Monitoring | Basic CloudWatch logs | Structured logging + alarms + dashboard |
| CI/CD | Manual bash script | GitHub Actions |

---

## 9. Roadmap

| Phase | Goal | Key Actions |
|-------|------|-------------|
| **PoC (Current)** | Validate end-to-end RAG pipeline | Manual deploy, Haiku model, Vercel demo |
| **MVP (Next)** | Harden, automate, and scale | Cognito auth, CI/CD, multi-AZ OpenSearch, streaming |
| **Production** | Enterprise-grade | VPC, CloudFront, re-ranking, monitoring dashboard |

---

## Appendix A – OpenSearch Configuration

| Parameter | Value |
|-----------|-------|
| **Domain Name** | `tastetrend-demo` |
| **Region** | `eu-central-1` |
| **Instance Type** | `t3.small.search` |
| **Nodes** | 1 (single-AZ) |
| **Storage** | 10 GB EBS gp2 |
| **Encryption** | AWS-managed KMS key |
| **Engine** | HNSW (`nmslib`) |
| **Similarity Metric** | Cosine |
| **Vector Dimension** | 1024 (Titan Embed v2) |
| **Index Name** | `reviews` |
| **Documents indexed** | 1,660 |

---

## Appendix B – Bedrock Agent Configuration

| Parameter | Value |
|-----------|-------|
| **Agent ID** | `IVEGCZX9LV` |
| **Alias** | `PKAKGJIGJF` (live-haiku) |
| **Version** | 5 |
| **Foundation Model** | `anthropic.claude-3-haiku-20240307-v1:0` |
| **Region** | `eu-central-1` |
| **Action Group** | `search_reviews` → `tastetrend-poc-search` Lambda |
| **Trace** | Enabled (`enableTrace=True`) |

---

✅ **Document Status:** Finalized for PoC phase.
