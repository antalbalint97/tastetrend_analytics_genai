# TasteTrend GenAI Infrastructure

Terraform infrastructure for the TasteTrend Proof-of-Concept, built entirely on AWS using a modular architecture.

---

## Overview
This project provisions a full GenAI pipeline integrating **Amazon Bedrock**, **OpenSearch**, **Lambda**, and **API Gateway**.

### Core Flow
1. **S3 Buckets** – Store raw, processed, and deployment artifacts.
2. **Lambda (ETL, Embedding, Proxy)** – Handle data processing, vector embedding, and API routing.
3. **OpenSearch Domain** – Hosts the vector index for semantic search.
4. **Knowledge Base (Bedrock)** – Uses OpenSearch as storage for embeddings.
5. **Bedrock Agent** – Interacts with the Knowledge Base to power GenAI queries.
6. **API Gateway** – Exposes the Bedrock Agent through an HTTP endpoint.
7. **IAM** – Provides least-privilege roles for Lambdas, EC2, and Bedrock services.

---

## Module Structure
| Module | Purpose |
|---------|----------|
| `modules/s3` | Secure versioned storage |
| `modules/iam` | IAM roles and policies |
| `modules/opensearch` | Managed OpenSearch domain |
| `modules/lambda` | ETL, Embedding, and Proxy functions |
| `modules/api` | API Gateway HTTP endpoint |
| `modules/bedrock_agent` | Bedrock conversational agent |

---
