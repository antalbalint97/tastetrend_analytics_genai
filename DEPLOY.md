# TasteTrend GenAI — Deployment & Validation Guide

Quick-start guide for deploying and verifying the TasteTrend PoC backend.

---

## Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Terraform >= 1.7.0
- Python 3.11+ (for Lambda packaging)
- `jq` (optional, for pretty-printing JSON)

---

## 1. Deploy Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan \
  -var="api_key_hash=$(echo -n 'YOUR_API_KEY' | sha256sum | awk '{print $1}')" \
  -var="opensearch_master_password=YourStr0ngP@ssword!"

# Apply
terraform apply \
  -var="api_key_hash=$(echo -n 'YOUR_API_KEY' | sha256sum | awk '{print $1}')" \
  -var="opensearch_master_password=YourStr0ngP@ssword!"
```

After apply, note the outputs:
- `invoke_url` — API Gateway endpoint
- `opensearch_endpoint` — OpenSearch domain endpoint
- `search_lambda_name` — Name of Search Lambda
- `proxy_lambda_name` — Name of Proxy Lambda
- `embedding_lambda_name` — Name of Embedding Lambda

---

## 2. Build & Upload Lambda Packages

The deployment script installs Python dependencies from `requirements-lambda.txt`
into a temporary build directory, copies the Lambda source code on top, and
creates self-contained zip artifacts.

```bash
# From the repo root — build + upload version 6.1
./deployment_pipeline_bash.sh 6.1 eu-central-1 <ARTIFACTS_BUCKET>
```

This produces four zip artifacts uploaded to S3 with keys that match Terraform:

| Lambda    | S3 key                            |
|-----------|-----------------------------------|
| ETL       | `lambda/etl-6.1.zip`              |
| Embedding | `lambda/embedding-6.1.zip`        |
| Search    | `lambda/search-6.1.zip`           |
| Proxy     | `lambda/proxy-6.1.zip`            |

Then update the Lambda functions if the version has changed:
```bash
cd terraform
terraform apply \
  -var="lambda_version=6.1" \
  -var="api_key_hash=$(echo -n 'YOUR_API_KEY' | sha256sum | awk '{print $1}')" \
  -var="opensearch_master_password=YourStr0ngP@ssword!"
```

---

## 3. Run Embedding Ingestion

Invoke the embedding Lambda to index processed reviews into OpenSearch:

```bash
aws lambda invoke \
  --function-name tastetrend-poc-embedding \
  --region eu-central-1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"s3_csv_uri": "s3://tastetrend-poc-processed-<ACCOUNT_ID>/processed/processed_final.csv", "os_index": "reviews"}' \
  /tmp/embed_output.json

cat /tmp/embed_output.json | jq .
```

---

## 4. Test the Backend

### Set environment variables

```bash
export AWS_REGION=eu-central-1
export SEARCH_LAMBDA_NAME=tastetrend-poc-search
export PROXY_LAMBDA_NAME=tastetrend-proxy-lambda
export API_GATEWAY_URL=https://<API_ID>.execute-api.eu-central-1.amazonaws.com
export API_GATEWAY_KEY=YOUR_API_KEY
export OPENSEARCH_DOMAIN_NAME=tastetrend-demo
```

### Run tests

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

---

## 5. Test the /query Endpoint Manually

```bash
curl -s -X POST "${API_GATEWAY_URL}/query" \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"query": "What do customers complain about in Riverside?"}' | jq .
```

Expected response shape:
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

---

## Environment Variables Reference

| Variable | Used By | Description |
|---|---|---|
| `AWS_REGION` | All Lambdas, scripts | AWS region (default: eu-central-1) |
| `OS_ENDPOINT` | Embedding Lambda | OpenSearch domain endpoint |
| `OS_INDEX` | Embedding Lambda | Index name (default: reviews) |
| `OPENSEARCH_URL` | Search Lambda | Full OpenSearch URL with https:// |
| `INDEX_NAME` | Search Lambda | Index name (default: reviews) |
| `AGENT_ID` | Proxy Lambda | Bedrock Agent ID |
| `AGENT_ALIAS` | Proxy Lambda | Bedrock Agent Alias ID |
| `API_KEY_HASH` | Proxy Lambda | SHA256 hash of the API key |

---

## Verification Checklist

Use this checklist before the final demo:

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
