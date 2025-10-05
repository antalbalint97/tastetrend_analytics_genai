# Infrastructure Decision Record – TasteTrend RAG (GenAI Proof of Concept)

**Purpose**  
Document architectural and infrastructure decisions for the **Retrieval-Augmented Generation (RAG)** pipeline developed for the TasteTrend AWS GenAI Proof of Concept (PoC).

**Goal**  
Demonstrate that restaurant review data can be semantically retrieved and used to generate grounded, factual responses through **Amazon Bedrock** models integrated with **OpenSearch Serverless**.

---

## 1. Context and Objectives

This Proof of Concept focuses on validating the **RAG pipeline’s retrieval quality** and **Bedrock integration**.  
The goal is not scalability or automation, but **accuracy, transparency, and speed of iteration**.

The system enables natural-language queries such as:  
_“What do customers like most about Uptown?”_  
and returns evidence-based insights grounded in actual reviews.

---

## 2. Architecture Summary

| Component | Purpose | Implementation |
|------------|----------|----------------|
| **Data Source** | Cleaned and processed restaurant reviews | S3 bucket `tastetrend-dev-processed-*` |
| **Embedding Model** | Generate semantic vector embeddings | Bedrock Titan Embed Text v2 (1024D) |
| **Vector Store** | Store and search embeddings | OpenSearch Serverless (`tastetrend-rag`) |
| **Execution** | One-off embedding & ingestion | Manual EC2 batch run |
| **Access Control** | Secure data and model access | IAM roles (ingest/query) |

---

## 3. Key Decisions

### 3.1 OpenSearch Serverless
**Decision:** Use OpenSearch Serverless for vector storage and retrieval.  
**Rationale:**  
- Fully managed and cost-efficient for PoC workloads.  
- Native integration with Bedrock SDKs and boto3.  
- Supports cosine similarity with Titan embeddings.  
**Trade-off:** Single-AZ setup without replication.  
**Mitigation (MVP):** Move to multi-AZ domain with replica shards and fine-grained access control.

---

### 3.2 Embedding Generation with Bedrock Titan
**Decision:** Use `amazon.titan-embed-text-v2:0` for embeddings.  
**Rationale:**  
- Native AWS model ensures consistency and compatibility with Bedrock Agents.  
- No external dependencies or custom hosting required.  
**Trade-off:** Latency increases with batch size.  
**Mitigation (MVP):** Parallelize embedding requests via Lambda and Step Functions.

---

### 3.3 Manual EC2 Execution (Chosen for PoC)
**Decision:** Run the ingestion pipeline manually on EC2.  
**Rationale:**  
- Fastest route to execution without deployment overhead.  
- Complete transparency and manual control for debugging.  
- Low cost due to short-lived instance (terminated post-run).  
**Trade-off:** Manual trigger, no retry logic, and dependency on local credentials.  
**Mitigation (MVP):** Replace with automated ingestion using **Lambda + Step Functions**.

---

## 4. Data Workflow

1. Load dataset (`processed_final.parquet`) from S3.  
2. Split reviews into overlapping text chunks (~1200 chars, 20% overlap).  
3. Generate Titan embeddings in batches of 32.  
4. Combine embeddings with metadata (`review_id`, `restaurant_name`, `rating`, etc.).  
5. Bulk index documents into OpenSearch (`reviews_v1`).  
6. Validate retrieval with known queries.

**Outcome:**  
- 1930 chunks indexed successfully.  
- 0 failures.  
- Queries returned relevant, semantically consistent results.

---

## 5. Security & IAM

| Role | Purpose | Permissions |
|------|----------|-------------|
| `tastetrend-rag-ingest-role` | Data ingestion | Read from S3, write to OpenSearch, invoke Bedrock |
| `tastetrend-rag-query-role` | Query access | Read-only OpenSearch access |

**Security Controls:**
- Principle of least privilege applied.  
- HTTPS enforced, IAM-based domain access.  
- Temporary credentials via STS.  
- *Next Step:* Use Secrets Manager and VPC-restricted endpoints.

---

## 6. Observability & Validation

**Logging:**  
- Console logs with progress updates every 500 embeddings.  
- Summary output at completion.

```
Starting review embedding and indexing...
Loaded 1660 reviews. Starting embedding and indexing...
Progress: 1500 chunks processed (1500 indexed, 0 failed)
--- Ingestion complete ---
Indexed: 1930 | Failed: 0
```

**Validation:**  
- Tested retrieval on sample business queries.  
- Verified cosine similarity and clustering consistency.

**Performance Targets:**

| Metric | Target | Notes |
|---------|---------|-------|
| Embedding throughput | 500–1000 docs/min | Titan v2, single-threaded |
| Query latency | <200 ms | HNSW engine |
| Recall@6 | ≥85% | Based on semantic evaluation |

---

## 7. Infrastructure as Code

**Terraform Modules**
- `opensearch_domain` → manages RAG collection  
- `iam_roles` → defines ingest/query roles  
- `variables.tf` → defines region, endpoints, and buckets  

**Standards**
- Naming: `tastetrend-dev-*`  
- Tagged for environment and cost tracking  

**Future (MVP):**
- Transition to a production-grade serverless workflow with AWS Lambda and Step Functions orchestration

---

## 8. Roadmap

| Phase | Goal | Key Actions |
|-------|------|--------------|
| **PoC (Current)** | Validate end-to-end retrieval | Manual EC2 run, minimal IAM |
| **MVP (Next)** | Automate ingestion & harden security | Lambda + Step Functions, CloudWatch metrics |
| **Production** | Scale and integrate | Multi-AZ OpenSearch, re-ranking, API Gateway integration |

---

## 9. General Trade-offs & Mitigations

| Area | Trade-off | Mitigation (MVP) |
|------|------------|------------------|
| **Scalability** | Manual execution | Step Functions orchestration |
| **Resilience** | Single node | Multi-AZ setup |
| **Security** | Public endpoint | VPC restriction |
| **Automation** | Manual ingestion | Lambda event triggers |
| **Versioning** | Manual file tracking | Index alias-based versioning |

---

## 10. Outcome Summary

The TasteTrend RAG PoC validated the **core technical hypothesis** — that OpenSearch Serverless with Titan embeddings can deliver accurate, low-latency semantic retrieval for restaurant reviews.  

Manual EC2 execution was a **defensible and deliberate choice**, balancing speed, cost, and transparency in early experimentation.  
The next phase will focus on **automation, security, and scalability** using fully serverless ingestion pipelines and integrated Bedrock orchestration.

---

## Appendix A – OpenSearch Configuration

| Parameter | Value |
|------------|--------|
| **Collection Name** | `tastetrend-rag` |
| **Region** | `eu-central-1` |
| **Encryption** | AWS-managed key |
| **Network Policy** | Temporarily public |
| **Access Policy** | IAM-based (ingest/query roles) |
| **Engine** | HNSW (`nmslib`) |
| **Similarity Metric** | Cosine |
| **Vector Dimension** | 1024 |
| **Index Name** | `reviews_v1` |
| **HNSW Params** | `m=16`, `ef_construction=128`, `ef_search=128` |

---

## Appendix B – Dependencies & Environment

- **Runtime:** Python 3.11 (PoC), 3.9 (EC2 AMI)  
- **Dependencies:** boto3, opensearch-py, pandas, pyarrow, s3fs, tqdm, python-dotenv  
- **Instance:** EC2 `t3.medium` (Amazon Linux 2023)  
- **Execution Duration:** ~15 minutes (embedding + indexing)  
- **Termination:** Instance destroyed post-run to prevent costs  

---

✅ **Document Status:** Finalized for PoC phase.  
Follow-up docs:  
- `infrastructure_bedrock_agent.md`  
- `infrastructure_api_gateway.md`
