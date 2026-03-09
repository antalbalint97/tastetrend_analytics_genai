# TasteTrend Analytics — GenAI PoC

## Overview

TasteTrend Analytics is a Proof-of-Concept RAG (Retrieval-Augmented Generation) system that enables restaurant chain operators to query customer review data using natural language. Built for a client demonstration, the system ingests raw review CSVs, cleans and standardises them through an ETL pipeline, generates semantic embeddings with Amazon Titan Embed Text v2, and stores them in an OpenSearch vector index. A Bedrock Agent (Claude 3 Haiku) orchestrates retrieval and answer generation so end-users receive evidence-grounded insights — e.g. *"What do customers complain about at the Riverside location?"* — with source reviews attached. AWS Bedrock Agent was chosen over a hand-rolled RAG chain because it handles tool-use orchestration, conversation memory, and guardrails out of the box, reducing custom code and accelerating PoC delivery.

---

## Architecture

### Data Ingestion Pipeline

```
S3 (raw CSVs)
     │
     ▼
ETL Lambda ─── validates, deduplicates, normalises ──▶ S3 (processed parquet + CSV)
                                                              │
                                                              ▼
                                                     Embedding Lambda
                                                     (Titan Embed v2, 1024-dim)
                                                              │
                                                              ▼
                                                     OpenSearch Managed Domain
                                                     (KNN index, t3.small.search)
```

### Query Pipeline

```
Vercel Frontend
     │
     ▼
API Gateway (HTTP, POST /query)
     │
     ▼
Proxy Lambda ── auth (SHA-256 API key) ──▶ Bedrock Agent (Claude 3 Haiku)
                                                │
                                                ▼
                                          Search Action Group
                                                │
                                                ▼
                                          Search Lambda
                                          (Titan embed query → KNN search)
                                                │
                                                ▼
                                          OpenSearch (vector similarity)
                                                │
                                          results returned to Agent
                                                │
                                                ▼
                                          Bedrock Agent generates grounded answer
                                                │
                                                ▼
                                          Proxy Lambda returns JSON to frontend
```

### Full-Stack Diagram (ASCII)

```
S3 (raw) → ETL Lambda → S3 (processed) → Embedding Lambda → OpenSearch
                                                                  ↓
Vercel Frontend → API GW → Proxy Lambda → Bedrock Agent (Haiku) → Search Lambda → OpenSearch
```

---

## Component Decisions & Trade-offs

### OpenSearch Managed

Native KNN support  ✅ HNSW via `knn_vector` |
AWS-native auth  ✅ IAM SigV4 |
PoC cost  ~$30/mo (t3.small) |
Terraform support  ✅ `aws_opensearch_domain` |
Metadata filtering  ✅ term queries + KNN |

**Decision:** OpenSearch Managed was selected because it provides native KNN with HNSW, first-class Terraform support, IAM-based access control, and the lowest cost for a single-node PoC.

### Bedrock Agent vs Direct Lambda RAG

**Decision:** Bedrock Agent orchestrates the retrieval → generation flow instead of a custom Lambda chain. The Agent handles tool-use routing (deciding when to call the search action group), conversation memory via session IDs, and prompt management — all of which would require significant custom code in a direct Lambda RAG. For a PoC where iteration speed matters more than fine-grained control, the managed Agent dramatically reduces development time. The trade-off is less control over prompt chaining and retry logic, which would become relevant at production scale.

### Claude 3 Haiku vs Sonnet (cost vs quality)

| Model | Input cost (per 1K tokens) | Output cost (per 1K tokens) | Latency |
|---|---|---|---|
| Haiku | $0.00025 | $0.00125 | ~1-2s |
| Sonnet | $0.003 | $0.015 | ~3-5s |

**Decision:** Haiku was chosen for the PoC because it is **12× cheaper** on input tokens and delivers sub-2-second responses for the review summarisation task. Quality is sufficient for grounded Q&A over structured reviews — the retrieval step provides the factual context, so the model primarily needs to synthesise rather than reason deeply. If answer quality becomes a concern in production, upgrading to Sonnet requires only a model ARN change in `terraform/modules/bedrock_agent/bedrock_agent.tf`.

### API Gateway + Proxy Lambda vs Direct Bedrock Invocation from Frontend

**Decision:** A Proxy Lambda sits between API Gateway and Bedrock Agent to:
1. **Authenticate requests** — SHA-256 API key validation without exposing AWS credentials to the frontend.
2. **Normalise the response** — the Bedrock Agent streaming format is complex; the proxy extracts `answer`, `results[]`, `conversation_id`, and `latency_ms` into a stable frontend-friendly JSON contract.
3. **Decouple frontend/backend** — the frontend calls a single REST endpoint; the backend can swap between Bedrock Agent, direct model invocation, or a different provider without frontend changes.

The alternative (direct Bedrock SDK calls from the frontend) would require embedding AWS credentials in client-side code, which is a security anti-pattern.

### Vercel Frontend vs S3 Static Hosting

**Decision:** Vercel was chosen for the Next.js frontend because it provides:
- Zero-config builds and global CDN edge deployment
- Serverless API routes (used for proxying during development)
- Built-in preview deployments per PR

S3 + CloudFront would work for a static SPA but requires manual CloudFront distribution setup and invalidation management. For a PoC, Vercel's developer experience is significantly faster. For production, migrating to CloudFront + S3 would reduce external dependencies.

---

## Repository Structure

```
tastetrend_analytics_genai/
├── README.md                          # This file
├── deployment_pipeline_bash.sh        # Build + upload Lambda ZIPs to S3
├── requirements-lambda.txt            # Python deps bundled into Lambda ZIPs
├── requirements.txt                   # Local development dependencies
├── package.json                       # Node/Vercel config (frontend)
│
├── terraform/                         # Infrastructure as Code
│   ├── main.tf                        # Root module — wires all resources together
│   ├── variables.tf                   # Input variables (project, region, api_key_hash, etc.)
│   ├── outputs.tf                     # Exported values (invoke_url, agent_id, etc.)
│   ├── providers.tf                   # AWS provider config (>= 5.0)
│   ├── terraform.tfvars               # Variable overrides (lambda_version, api_key_hash)
│   └── modules/
│       ├── api/                       # API Gateway v2 (HTTP) — POST /query route + CORS
│       ├── bedrock_agent/             # Bedrock Agent + search action group + alias
│       ├── iam/                       # IAM roles for ETL, Embedding, Search, Proxy, Agent
│       ├── lambda/
│       │   ├── etl/                   # ETL Lambda (Python 3.11, 15min, 3GB, pandas layer)
│       │   ├── embedding/             # Embedding Lambda (Python 3.11, 15min, 3GB)
│       │   ├── search/                # Search Lambda (Python 3.11, 30s, 512MB)
│       │   └── proxy/                 # Proxy Lambda (Python 3.11, 60s)
│       ├── opensearch_managed/        # Managed OpenSearch domain (t3.small, gp3 20GiB)
│       ├── opensearch_serverless/     # DEPRECATED — kept for reference
│       ├── s3/                        # S3 bucket module (versioning, encryption, public block)
│       └── tags/                      # Default tags output module
│
├── src/
│   ├── lambda_functions/              # Lambda handler source code
│   │   ├── proxy_handler.py           # API GW → Bedrock Agent proxy with auth
│   │   ├── search_reviews.py          # KNN vector search with location filtering
│   │   ├── embedding_handler.py       # Batch embed + index into OpenSearch
│   │   ├── etl_handler.py             # ETL orchestrator (optional embedding trigger)
│   │   └── etl_core.py                # ETL core — raw → processed transformation
│   ├── etl/                           # ETL library (ReviewLoader, validation, bias audit)
│   │   ├── etl.py                     # Schema normalisation, dedup, type coercion
│   │   └── etl_validation.py          # Automated data quality checks
│   ├── api/                           # Client utilities
│   │   ├── query_client.py            # HTTP client for /query endpoint + smoke test
│   │   └── eval.py                    # Automated RAG evaluation (keyword + semantic accuracy)
│   └── utils/
│       └── logger.py                  # Shared logging configuration
│
├── scripts/
│   └── test_backend.sh                # CLI test harness (search, proxy, api, domain modes)
│
├── docs/                              # Design documentation
│   ├── data_integrity.md              # Data exploration, standardisation & validation report
│   ├── infrastructure_etl.md          # ETL infrastructure decision record
│   ├── infrastructure_rag.md          # RAG infrastructure decision record
│   ├── cost.md                        # AWS cost estimates (PoC + MVP)
│   └── mvp-plan.md                    # PoC → Production MVP roadmap
│
└── notebooks/                         # Jupyter notebooks
    ├── data_exploration.ipynb         # EDA on raw review data
    └── demo.ipynb                     # End-to-end demo notebook
```

---

## Deployment

### Prerequisites

- **AWS CLI v2** configured with credentials that have admin-level access
- **Terraform >= 1.7.0**
- **Python 3.11+** (for Lambda packaging)
- **jq** (optional, for pretty-printing JSON responses)

### Step 1 — Build & Upload Lambda Packages

The deployment script installs Python dependencies from `requirements-lambda.txt` into a temporary build directory, copies the Lambda source code on top, and creates self-contained ZIP artifacts.

```bash
# From the repo root — build + upload (version, region, artifacts bucket)
./deployment_pipeline_bash.sh 6.5 eu-central-1 <ARTIFACTS_BUCKET>
```

This produces four ZIP artifacts uploaded to S3:

| Lambda    | S3 key                     |
|-----------|----------------------------|
| ETL       | `lambda/etl-6.5.zip`       |
| Embedding | `lambda/embedding-6.5.zip` |
| Search    | `lambda/search-6.5.zip`    |
| Proxy     | `lambda/proxy-6.5.zip`     |

On the first run, the script will also prompt to upload raw data files to the raw S3 bucket.

### Step 2 — Initialise Terraform

```bash
cd terraform
terraform init
```

### Step 3 — Review and Apply Infrastructure

```bash
# Review the plan
terraform plan \
  -var="api_key_hash=$(echo -n 'YOUR_API_KEY' | sha256sum | awk '{print $1}')" \
  -var="lambda_version=6.5"

# Apply
terraform apply \
  -var="api_key_hash=$(echo -n 'YOUR_API_KEY' | sha256sum | awk '{print $1}')" \
  -var="lambda_version=6.5"
```

After apply, note the outputs:
- `invoke_url` — API Gateway endpoint
- `opensearch_endpoint` — OpenSearch domain endpoint
- `agent_id` / `agent_alias_id` — Bedrock Agent identifiers
- `search_lambda_name` / `proxy_lambda_name` / `embedding_lambda_name`

### Step 4 — Run Embedding Ingestion

Invoke the Embedding Lambda to index processed reviews into OpenSearch:

```bash
aws lambda invoke \
  --function-name tastetrend-poc-embedding \
  --region eu-central-1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"s3_csv_uri": "s3://tastetrend-poc-processed-<ACCOUNT_ID>/processed/processed_final.csv", "os_index": "reviews"}' \
  /tmp/embed_output.json

cat /tmp/embed_output.json | jq .
```

> **Note:** If the OpenSearch index exists with a different vector dimension (e.g. 1536 instead of 1024), the Embedding Lambda auto-detects and recreates mismatched indices. You can also delete it manually:
> ```bash
> curl -X DELETE "https://<OS_ENDPOINT>/reviews" \
>   --aws-sigv4 "aws:amz:eu-central-1:es" \
>   --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY"
> ```

### Step 5 — Set Environment Variables and Test

```bash
export AWS_REGION=eu-central-1
export SEARCH_LAMBDA_NAME=tastetrend-poc-search
export PROXY_LAMBDA_NAME=tastetrend-proxy-lambda
export API_GATEWAY_URL=https://<API_ID>.execute-api.eu-central-1.amazonaws.com
export API_GATEWAY_KEY=YOUR_API_KEY
export OPENSEARCH_DOMAIN_NAME=tastetrend-demo
```

```bash
# Test Search Lambda directly
./scripts/test_backend.sh search "What do customers complain about in Riverside?"

# Test Proxy Lambda directly
./scripts/test_backend.sh proxy "Which location has the most complaints about waiting times?"

# Test API Gateway /query endpoint
./scripts/test_backend.sh api "What do customers say about staff friendliness?"

# Check OpenSearch domain status
./scripts/test_backend.sh domain
```

### Step 6 — Test the /query Endpoint Manually

```bash
curl -s -X POST "${API_GATEWAY_URL}/query" \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"query": "What do customers complain about in Riverside?"}' | jq .
```

Expected response:

```json
{
  "answer": "Customers most often complain about waiting times...",
  "results": [
    {
      "review_id": "123",
      "restaurant_name": "Riverside",
      "rating": 2.9,
      "text": "We waited 40 minutes for our table..."
    }
  ],
  "conversation_id": "abc-123",
  "latency_ms": 1840
}
```

### Verification Checklist

- [ ] `terraform apply` completes without errors
- [ ] OpenSearch domain is in `Active` state (`./scripts/test_backend.sh domain`)
- [ ] Embedding Lambda successfully indexes reviews (check CloudWatch logs)
- [ ] Search Lambda returns `results[]` with `review_id`, `restaurant_name`, `rating`, `text`
- [ ] Proxy Lambda returns `answer`, `results`, `conversation_id`, `latency_ms`
- [ ] `POST /query` via API Gateway returns a valid JSON response
- [ ] CORS headers are present in API Gateway response
- [ ] API key validation works (401 without key, 200 with valid key)
- [ ] Bedrock Agent uses the search tool (visible in trace logs)
- [ ] End-to-end: a natural language question returns a grounded answer with evidence

---

## Configuration

### Terraform Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `project` | `string` | `"tastetrend"` | Project name prefix for resource naming |
| `env` | `string` | `"poc"` | Deployment environment (dev, staging, prod) |
| `region` | `string` | `"eu-central-1"` | AWS region |
| `profile` | `string` | `null` | Optional AWS CLI profile name |
| `lambda_version` | `string` | `"0.1"` | Lambda ZIP version suffix (e.g. `6.5`) |
| `api_key_hash` | `string` | — (required, sensitive) | SHA-256 hash of the API key |
| `index_name` | `string` | `"reviews"` | OpenSearch index name |

### Lambda Environment Variables

| Variable | Lambda | Description |
|---|---|---|
| `RAW_BUCKET` | ETL | Source S3 bucket for raw review files |
| `PROCESSED_BUCKET` | ETL | Destination S3 bucket for processed output |
| `OS_ENDPOINT` | Embedding | OpenSearch domain endpoint (without `https://`) |
| `OS_INDEX` | Embedding | Index name (default: `reviews`) |
| `VECTOR_DIM` | Embedding | Embedding dimension (default: `1024`) |
| `BATCH_SIZE` | Embedding | Docs per embedding batch (default: `8`) |
| `OPENSEARCH_URL` | Search | Full OpenSearch URL (with `https://`) |
| `INDEX_NAME` | Search | Index name (default: `reviews`) |
| `KNOWN_LOCATIONS` | Search | Comma-separated location names for filtering |
| `AGENT_ID` | Proxy | Bedrock Agent ID |
| `AGENT_ALIAS` | Proxy | Bedrock Agent Alias ID |
| `API_KEY_HASH` | Proxy | SHA-256 hash of the frontend API key |

### Script Environment Variables

| Variable | Script | Description |
|---|---|---|
| `AWS_REGION` | `test_backend.sh` | AWS region (default: `eu-central-1`) |
| `SEARCH_LAMBDA_NAME` | `test_backend.sh` | Search Lambda function name |
| `PROXY_LAMBDA_NAME` | `test_backend.sh` | Proxy Lambda function name |
| `API_GATEWAY_URL` | `test_backend.sh` | API Gateway base URL |
| `API_GATEWAY_KEY` | `test_backend.sh` | API key for `x-api-key` header |
| `OPENSEARCH_DOMAIN_NAME` | `test_backend.sh` | Managed OpenSearch domain name |
| `TT_API_URL` | `query_client.py` | API Gateway URL for evaluation client |
| `TT_API_KEY` | `query_client.py` | API key for evaluation client |

---

## Known Limitations (PoC Scope)

These limitations are **intentional for a Proof of Concept** and would be addressed in an MVP phase (see [docs/mvp-plan.md](docs/mvp-plan.md)).

| Area | Limitation | Why Acceptable for PoC |
|---|---|---|
| **Authentication** | SHA-256 API key check (shared secret) — no user identity, no token rotation | Sufficient to prevent unauthenticated access during demos; a single client is the only consumer |
| **OpenSearch** | Single `t3.small.search` node, no replicas, no Multi-AZ | Keeps cost at ~$30/mo; the dataset is small (~2K documents) and there is no SLA requirement |
| **Data pipeline** | Manual trigger via `aws lambda invoke` — no scheduled or event-driven ingestion | Data changes infrequently during PoC; manual control gives full visibility for debugging |
| **CI/CD** | Deployment via `deployment_pipeline_bash.sh` — no automated pipeline | Two developers; the bash script is auditable and fast enough for the PoC iteration cycle |
| **Monitoring** | CloudWatch default logs only — no structured logging, no alarms, no dashboards | Acceptable when the team is the only user; production would require CloudWatch Alarms + dashboards |
| **Multi-tenancy** | Single restaurant chain, hardcoded location list | PoC validates the technical approach for one client; multi-tenancy is an MVP concern |
| **Error handling** | Basic try/catch with CloudWatch logging — no dead-letter queues, no retry policies | Failures during PoC are investigated manually via CloudWatch; DLQ is an MVP requirement |
| **Frontend** | Deployed on Vercel (external to AWS) — no WAF, no CloudFront integration | Speed of iteration; production would use CloudFront + S3 or consolidate into AWS |
| **Security** | OpenSearch access policy scoped to account (not VPC-restricted), no Secrets Manager | Acceptable in a demo environment; production requires VPC endpoints and Secrets Manager |
| **Testing** | No automated tests — validation relies on `test_backend.sh` and manual smoke tests | PoC scope; MVP would introduce pytest unit tests and integration test suite |
| **Cost controls** | No budget alarms or reserved capacity | Monthly PoC cost is <$100; production would add AWS Budgets alerts |

---

## Further Documentation

- [docs/cost.md](docs/cost.md) — AWS cost estimates (PoC and scale to 100 DAU MVP)
- [docs/mvp-plan.md](docs/mvp-plan.md) — From PoC to Production MVP roadmap
- [docs/data_integrity.md](docs/data_integrity.md) — Data exploration, standardisation & validation report
- [docs/infrastructure_etl.md](docs/infrastructure_etl.md) — ETL infrastructure decision record
- [docs/infrastructure_rag.md](docs/infrastructure_rag.md) — RAG infrastructure decision record
