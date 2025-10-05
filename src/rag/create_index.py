# create_index.py
# Purpose: create an OpenSearch index for RAG with HNSW kNN vectors.

import os
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth


# --- Configuration from environment ---
REGION = os.environ["AWS_REGION"]
OS_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"] 
OS_INDEX = os.environ.get("OS_INDEX", "reviews_v1")


# --- AWS auth (SigV4) ---
session = boto3.Session()
creds = session.get_credentials()
awsauth = AWS4Auth(
    creds.access_key,
    creds.secret_key,
    REGION,
    "aoss",                      # service ID for Amazon OpenSearch Service (use "aoss" for Serverless)
    session_token=creds.token  # include STS session token if present
)

# Normalize host for the client (strip scheme if provided)
host = OS_ENDPOINT.replace("https://", "").replace("http://", "").split("/")[0]

# --- OpenSearch client ---
client = OpenSearch(
    hosts=[{"host": host, "port": 443}],
    http_auth=awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)


def main() -> None:
    """Create the index if it doesn't already exist."""
    if client.indices.exists(index=OS_INDEX):
        print(f"Index {OS_INDEX} already exists")
        return

    body = {
        "settings": {
            "index": {
                "knn": True,
                "knn.algo_param.ef_search": 128
            }
        },
        "mappings": {
            "properties": {
                "vector": {
                    "type": "knn_vector",
                    "dimension": 1024,
                    "method": {
                        "name": "hnsw",
                        "space_type": "cosinesimil",
                        "engine": "nmslib",
                        "parameters": {"m": 16, "ef_construction": 128}
                    }
                },
                "chunk_text": {"type": "text"},
                "location":   {"type": "keyword"},
                "menu_item":  {"type": "keyword"},
                "rating":     {"type": "float"},
                "sentiment":  {"type": "keyword"},
                "review_id":  {"type": "keyword"},
                "ts":         {"type": "date"}
            }
        }
    }

    client.indices.create(index=OS_INDEX, body=body)
    print(f"Created index {OS_INDEX}")


if __name__ == "__main__":
    main()
