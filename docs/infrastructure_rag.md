# Infrastructure Decisions – TasteTrend RAG (GenAI POC)

**Purpose:**  
Document architecture, infrastructure, and operational decisions for the **Retrieval-Augmented Generation (RAG)** pipeline of the TasteTrend AWS GenAI Proof of Concept.  

**Scope:**  
Covers the OpenSearch configuration, Bedrock embedding setup, IAM design, data ingestion strategy, and roadmap for integrating the RAG layer with Bedrock Agents and API Gateway in the next phases.

---

## System Overview

The RAG system enables semantic search and contextual retrieval of restaurant reviews from processed data.  
It provides a **retrieval layer** that augments Bedrock’s generative models with factual, up-to-date review information stored in OpenSearch.  

**Goal:** Empower business analysts to query reviews in natural language (e.g., _“What do customers like most about Uptown?”_) and receive grounded, evidence-based insights rather than hallucinated responses.

---

## OpenSearch Domain Configuration

- **Engine Version:** OpenSearch 2.13  
- **Instance Type:** `t3.small.search` (single node, cost-optimized for PoC)  
- **Storage:** 20 GB gp3 EBS  
- **Encryption:** At rest + node-to-node encryption enabled  
- **TLS:** v1.2 minimum enforced  
- **Access Control:** IAM-based; restricted to designated ingestion and query roles  
- **Index Name:** `reviews_v1`

**Trade-offs:**
- ✅ Managed, serverless architecture suitable for a PoC workload  
- ✅ Easy integration with Bedrock and Python client libraries  
- ❌ Single-node setup (no redundancy or replication)  
- **Mitigation:** Future MVP will use multi-AZ domain with replica shards and fine-grained access control.

---

## Index Design

- **Vector Field:** `embedding` (`knn_vector`, dimension=1024)  
- **ANN Engine:** HNSW (`nmslib`) with cosine similarity  
- **Parameters:** `m=16`, `ef_construction=128`, `ef_search=128`  
- **Metadata Fields:**  
  - `review_id`, `review_chunk`, `restaurant_name`, `location`, `rating`, `sentiment`, `menu_item`

**Trade-offs:**
- ✅ Cosine similarity works optimally with normalized Titan embeddings  
- ✅ HNSW balances speed and recall  
- ❌ Slight accuracy loss compared to brute-force on small datasets  
- **Mitigation:** Increase `ef_search` dynamically or add re-ranking step during Bedrock orchestration.

---

## Embedding Generation

- **Model:** `amazon.titan-embed-text-v2:0`  
- **Embedding Dimension:** 1024  
- **Normalization:** Enabled  
- **Batch Size:** 32 (optimized for Bedrock API throughput)  
- **Runtime:** Python 3.11  
- **Dependencies:**: boto3, opensearch-py, pandas, pyarrow, s3fs, tqdm, python-dotenv


**Trade-offs:**
- ✅ AWS-native embedding service (no third-party dependency)  
- ✅ Consistent performance and compatibility with Bedrock Agents  
- ❌ Latency increases with larger batches  
- **Mitigation:** Parallelize embedding generation or move to Lambda-based async ingestion in MVP.

---

## Data Chunking & Ingestion Workflow

**Input Source:**  
`processed_final.parquet` from the **processed S3 bucket** (`tastetrend-dev-processed-<account_id>`).  

**Chunking Parameters:**
- **Chunk Size:** ~1200 characters  
- **Overlap:** 20% (~240 characters)  
- **Text Field:** `review_text`

**Ingestion Steps:**
1. Load processed dataset from S3.  
2. Split reviews into overlapping text chunks.  
3. Generate embeddings via Bedrock’s Titan model.  
4. Create JSON payloads with `{embedding + metadata}`.  
5. Bulk index documents into OpenSearch.

**Trade-offs:**
- ✅ Improves retrieval accuracy for long reviews.  
- ✅ Maintains context continuity.  
- ❌ Increases index storage (~15–25%).  
- **Mitigation:** Parameterize chunk size and overlap for performance tuning.

---

## Implementation Overview

**Location:** `src/rag/`  

### Primary Scripts
- `create_index.py` → defines OpenSearch schema  
- `ingest_parquet_to_opensearch.py` → chunks, embeds, and indexes  
- `test_query.py` → validates semantic search  

---

## Observability & Validation

### Logging
- Console logs for ingestion progress and errors  
- Batch-level progress updates every 500 embeddings  

### Validation
- Test retrieval relevance using known business queries  
- Measure similarity scores to confirm semantic grouping  

**Example Query Test:**
```python
results = search(
    "What do customers like most about the Uptown location?",
    k=6,
    filters={"location": "Uptown"}
)
```

### Performance Targets

| Metric | Target | Notes |
|---------|---------|-------|
| Embedding throughput | 500–1000 docs/min | Single-threaded, Titan v2 |
| Query latency | <200 ms | t3.small.search, HNSW engine |
| Recall@6 | ≥85% | Based on manual semantic evaluation |

---

## IAM & Security Design

### Execution Roles
- **tastetrend-rag-ingest-role** → read processed data, write to OpenSearch  
- **tastetrend-rag-query-role** → read-only access for API query Lambdas  

### Permissions
- S3 (read-only for processed data)  
- OpenSearch (write/read as per role)  
- Bedrock embedding model invocation  

### Security Controls
- Principle of least privilege enforced  
- Domain access limited by IAM ARN  
- HTTPS enforced; no public access  
- Temporary credentials via AWS STS  
- *Future:* Move secrets to AWS Secrets Manager  

**Trade-offs:**
- ✅ Secure and auditable IAM boundary  
- ✅ Roles aligned with least privilege principle  
- ❌ Slightly more complex IAM structure  
**Mitigation:** Reuse roles for Bedrock Agent access in Phase 5  

---

## Deployment Strategy

### Current (PoC)
- Domain created via Terraform (`opensearch_domain` module)  
- Python scripts executed locally using `.env` credentials  
- Manual ingestion into OpenSearch  

### Rejected Approaches
- Multi-index (per location) → unnecessary complexity  
- Local OpenSearch cluster → replaced by managed AWS service  

### Future (MVP)
- Package ingestion workflow as a Lambda function  
- Trigger automated embedding on dataset updates  
- Manage credentials and configurations via Terraform variables  

---

## Versioning & Artifacts

- **Dataset:** `processed_final.parquet` (timestamped)  
- **Index Version:** `reviews_v1`  
- **Script Versions:** Maintained in Git under `src/rag/`  
- **Artifacts:** Stored in `tastetrend-dev-artifacts-<account_id>`  

**Trade-offs:**
- ✅ Simple and transparent versioning  
- ❌ No automatic rollback mechanism  
**Mitigation:** Introduce alias-based versioning in future phases  

---

## IaC (Infrastructure as Code)

### Terraform Modules
- `opensearch_domain` – manages the RAG index cluster  
- `iam_roles` – defines ingestion/query roles  
- `variables.tf` – defines region, domain endpoint, and bucket URIs  

### Standards
- Naming convention: `tastetrend-dev-*`  
- Tags for ownership, environment, and cost tracking  

---

## Future Enhancements
- Add CloudWatch metrics for ingestion and query latency  
- Enable automated reindexing pipelines  
- Extend Terraform to deploy Bedrock Agent and API Gateway integration  

---

## Future MVP Roadmap

### Phase 5 – Bedrock Agent Integration
- Implement RAG orchestration with Bedrock Agents  
- Develop contextual prompt templates  
- Re-rank search results using Titan embeddings  

### Phase 6 – API Gateway Integration
- Deploy API endpoint with Lambda proxy  
- Implement request → retrieve → generate pipeline  
- Enable business-level question answering via HTTP requests  

---

## Scaling Roadmap
- Upgrade to `m6g.large.search` (multi-AZ)  
- Use Step Functions for parallel embedding generation  
- Add CloudWatch alerts for latency, recall, and throughput  

✅ This document captures infrastructure and design decisions for the TasteTrend RAG layer.  
Bedrock orchestration and API integration details will follow in `infrastructure_bedrock_agent.md` and `infrastructure_api_gateway.md`.
