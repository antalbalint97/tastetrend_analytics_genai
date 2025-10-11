# Lambda Module Suite

Contains all Lambda function modules for the TasteTrend GenAI pipeline:
- **ETL Lambda** – Handles data ingestion and preprocessing.
- **Embedding Lambda** – Generates vector embeddings and updates OpenSearch.
- **Proxy Lambda** – Acts as the API gateway handler for Bedrock Agent requests.

---

## ETL Lambda
**Purpose:**  
Performs extract–transform–load operations on review data, storing processed output in S3.

**Key Features**
- Uses a pre-uploaded ZIP from the artifacts bucket.
- Runs with Pandas/Numpy AWS layer.
- Configurable environment variables (S3 paths, OpenSearch endpoint, etc.).

**Inputs**
- `function_name`, `role_arn`, `zip_bucket`, `zip_key`, `lambda_version`, `env`

**Outputs**
- `lambda_name`, `lambda_arn`, `env_vars`

---

## Embedding Lambda
**Purpose:**  
Creates vector embeddings using Amazon Bedrock and stores them in OpenSearch.

**Key Features**
- Custom IAM role with access to Bedrock, KMS, OpenSearch, and S3.
- Uses custom OpenSearch layer.
- Configurable OpenSearch index and endpoint.

**Inputs**
- `os_endpoint`, `os_index`, `zip_bucket`, `zip_key`, `kms_key_arn`

**Outputs**
- Automatically deploys Lambda function `tt-embed`

---

## Proxy Lambda
**Purpose:**  
Serves as a lightweight API Gateway integration that forwards user queries to the Bedrock Agent.

**Key Features**
- Minimal IAM role (Lambda execution only)
- Configurable environment variables for agent routing
- Low-latency runtime optimized for short requests

**Inputs**
- `agent_id`, `agent_alias`, `api_key_hash`, `zip_bucket`, `zip_key`

**Outputs**
- Deploys `proxy-lambda` function for Bedrock Agent API integration
