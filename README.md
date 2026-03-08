# TasteTrend Analytics — GenAI PoC

A Proof-of-Concept RAG (Retrieval-Augmented Generation) pipeline for restaurant review analytics, built on AWS.

## Architecture

```
Frontend → API Gateway (POST /query) → Proxy Lambda → Bedrock Agent → Search Lambda → OpenSearch
```

**Key components:**
- **API Gateway** — single public `POST /query` endpoint
- **Proxy Lambda** — authenticates requests, invokes Bedrock Agent, returns structured JSON
- **Bedrock Agent** (Claude 3 Sonnet) — orchestrates tool use and generates grounded answers
- **Search Lambda** — performs vector similarity search against OpenSearch
- **OpenSearch** (managed domain) — stores review embeddings indexed by the Embedding Lambda
- **Embedding Lambda** — reads processed CSV from S3 and indexes Titan v2 embeddings

## Quick Start

See **[DEPLOY.md](DEPLOY.md)** for full deployment and testing instructions.

```bash
# Deploy infrastructure
cd terraform && terraform init && terraform apply

# Index embeddings
aws lambda invoke --function-name tastetrend-poc-embedding \
  --cli-binary-format raw-in-base64-out \
  --payload '{"s3_csv_uri":"s3://BUCKET/processed/processed_final.csv","os_index":"reviews"}' /tmp/out.json

# Test the endpoint
./scripts/test_backend.sh api "What do customers complain about?"
```

## Project Structure

| Path | Description |
|------|-------------|
| `terraform/` | Infrastructure as Code (Terraform modules) |
| `src/lambda_functions/` | Lambda handlers (ETL, Embedding, Search, Proxy) |
| `scripts/test_backend.sh` | Backend verification script |
| `DEPLOY.md` | Deployment & validation guide |
| `docs/` | Architecture and design docs |