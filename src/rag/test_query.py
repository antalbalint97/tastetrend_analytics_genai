# test_query.py
# Purpose: Test semantic search (RAG retrieval) using OpenSearch Serverless + Titan embeddings.

import os
import json
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth


# --- Configuration from environment ---
REGION = os.environ["AWS_REGION"]
OS_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]
OS_INDEX = os.environ.get("OS_INDEX", "reviews_v1")
BEDROCK_EMBED_MODEL = os.environ.get(
    "BEDROCK_EMBED_MODEL", "amazon.titan-embed-text-v2:0"
)


# --- AWS Auth (SigV4 for OpenSearch Serverless) ---
session = boto3.Session(region_name=REGION)
creds = session.get_credentials().get_frozen_credentials()
awsauth = AWS4Auth(
    creds.access_key,
    creds.secret_key,
    REGION,
    "aoss",                      # service ID for OpenSearch Serverless
    session_token=creds.token
)

# Normalize the host for OpenSearch client
host = OS_ENDPOINT.replace("https://", "").split("/")[0]

# --- OpenSearch Client ---
es = OpenSearch(
    hosts=[{"host": host, "port": 443}],
    http_auth=awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)

# --- Bedrock Client for Titan Embeddings ---
bedrock = session.client("bedrock-runtime", region_name=REGION)


# --- Helper: Embed query text into 1024-dim vector ---
def embed(q: str):
    """Call Bedrock Titan model to generate a text embedding."""
    body = {"inputText": q, "dimensions": 1024, "normalize": True}
    resp = bedrock.invoke_model(modelId=BEDROCK_EMBED_MODEL, body=json.dumps(body))
    out = json.loads(resp["body"].read())
    return out["embedding"]


# --- Main Search Logic ---
def search(q: str, k=6, filters=None, ef_search=128):
    """Perform vector similarity search with optional metadata filters."""
    vec = embed(q)
    query = {
        "size": k,
        "query": {
            "knn": {
                "vector": {
                    "vector": vec,
                    "k": k
                }
            }
        }
    }

    # Optional metadata filters (e.g., {"location": "Uptown"})
    if filters:
        filter_clauses = []
        for field, value in filters.items():
            if isinstance(value, list):
                filter_clauses.append({"terms": {field: value}})
            else:
                filter_clauses.append({"term": {field: value}})
        query = {
            "size": k,
            "query": {
                "bool": {
                    "filter": filter_clauses,
                    "must": [query["query"]]
                }
            }
        }

    params = {"knn.algo_param.ef_search": ef_search}
    res = es.search(index=OS_INDEX, body=query, params=params)
    hits = res["hits"]["hits"]
    return [{"score": h["_score"], **h["_source"]} for h in hits]


# --- Entry Point ---
if __name__ == "__main__":
    query_text = "What do customers like most about the Uptown location?"
    results = search(query_text, k=6, filters={"location": "Uptown"})

    print(f"\nQuery: {query_text}\n")
    for r in results:
        print(f"{r['score']:.3f} | {r.get('location')} | {r['chunk_text'][:140]}...")
