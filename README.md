# TasteTrend Analytics — GenAI PoC

A Proof-of-Concept RAG (Retrieval-Augmented Generation) pipeline for restaurant review analytics, built on AWS.

## Architecture

```
ETL Lambda ──► S3 (processed CSV)
                   │
           Embedding Lambda ──► OpenSearch (vector index)
                                       │
Vercel Frontend ──► API Gateway ──► Proxy Lambda ──► Bedrock Agent ──► Search Lambda ──► OpenSearch
```

**Full stack:**

| Layer | Component | Details |
|-------|-----------|---------|
| **Data ingestion** | ETL Lambda | Cleans raw review data, writes processed CSV to S3 |
| **Embedding** | Embedding Lambda | Reads CSV from S3, generates Titan v2 (1024-dim) vectors, indexes into OpenSearch |
| **Vector store** | OpenSearch (managed, t3.small.search) | Stores review embeddings; KNN search with optional location filter |
| **Orchestration** | Bedrock Agent | Claude 3 Haiku (`anthropic.claude-3-haiku-20240307-v1:0`) with action group for search |
| **Proxy** | Proxy Lambda | Authenticates API key, invokes Bedrock Agent, returns structured JSON |
| **API** | API Gateway | Single public `POST /query` endpoint |
| **Frontend** | Vercel (separate repo) | Next.js app calling the API Gateway endpoint |

**Agent alias:** `PKAKGJIGJF` (live-haiku → Version 5)

## Deployment

### 1. Build & upload Lambda packages

```bash
./deployment_pipeline_bash.sh        # builds zips, uploads to S3
```

### 2. Apply infrastructure

```bash
cd terraform
terraform init
terraform apply                      # uses terraform.tfvars
```

### Required environment variables (Terraform / Lambda)

| Variable | Description |
|----------|-------------|
| `AGENT_ID` | Bedrock Agent ID (output of `terraform apply`) |
| `AGENT_ALIAS` | Bedrock Agent Alias ID (see alias documented above) |
| `API_KEY_HASH` | SHA-256 hash of the API key used by the frontend |

See **[DEPLOY.md](DEPLOY.md)** for full deployment and validation instructions.

## Project Structure

| Path | Description |
|------|-------------|
| `terraform/` | Infrastructure as Code (Terraform modules) |
| `src/lambda_functions/` | Lambda handlers (ETL, Embedding, Search, Proxy) |
| `deployment_pipeline_bash.sh` | Builds Lambda zips and uploads to S3 |
| `scripts/test_backend.sh` | Backend verification script |
| `DEPLOY.md` | Deployment & validation guide |
| `docs/` | Architecture and design docs |