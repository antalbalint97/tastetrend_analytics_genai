import json
import boto3
import os
import requests
from requests_aws4auth import AWS4Auth

# === Environment variables ===
OPENSEARCH_URL = os.environ["OPENSEARCH_URL"]
INDEX_NAME = os.environ.get("INDEX_NAME", "reviews")
MODEL_ID = "amazon.titan-embed-text-v2:0"
REGION = os.environ.get("AWS_REGION", "eu-central-1")

# === AWS clients and auth setup ===
session = boto3.Session()
credentials = session.get_credentials().get_frozen_credentials()
awsauth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    REGION,
    "es",
    session_token=credentials.token
)

bedrock = boto3.client("bedrock-runtime", region_name=REGION)


def get_embedding(query: str):
    """Generate a Titan embedding vector for the query."""
    resp = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps({"inputText": query}),
        accept="application/json",
        contentType="application/json"
    )
    payload = json.loads(resp["body"].read())
    return payload["embedding"]


def _extract_query_from_event(event):
    """Extract the query string from various event formats (API GW, Bedrock Agent, direct)."""
    # Bedrock Agent action group format
    if "inputText" in event:
        return event["inputText"]

    # Check parameters array (Bedrock Agent action group)
    if "parameters" in event and isinstance(event["parameters"], list):
        for param in event["parameters"]:
            if param.get("name") == "query" and param.get("value"):
                return param["value"]

    # Standard body-based formats
    body = {}
    if isinstance(event.get("body"), str):
        try:
            body = json.loads(event["body"])
        except Exception:
            body = {}
    elif isinstance(event.get("body"), dict):
        body = event.get("body", {})

    return (
        body.get("query")
        or body.get("q")
        or event.get("query")
        or event.get("q")
    )


def lambda_handler(event, context):
    """Lambda entry point — compatible with both Bedrock Agent action group and direct invocation."""
    print("[INFO] Event received:", json.dumps(event, default=str))

    # --- Extract query ---
    query = _extract_query_from_event(event)

    if not query:
        print("[WARN] Missing 'query' parameter in request")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing 'query' parameter"})
        }

    print(f"[INFO] Processing search query: {query}")

    # --- Generate embedding ---
    emb = get_embedding(query)

    # --- Perform vector search in OpenSearch using `embedding` field ---
    search_payload = {
        "size": 5,
        "query": {"knn": {"embedding": {"vector": emb, "k": 5}}},
        "_source": ["review_id", "text", "restaurant_name", "rating"]
    }

    resp = requests.post(
        f"{OPENSEARCH_URL}/{INDEX_NAME}/_search",
        auth=awsauth,
        headers={"Content-Type": "application/json"},
        data=json.dumps(search_payload)
    )

    print(f"[INFO] OpenSearch status: {resp.status_code}")

    # --- Parse results safely ---
    hits = []
    try:
        response_json = resp.json()
        hits = response_json.get("hits", {}).get("hits", [])
    except Exception as e:
        print("[ERROR] Error parsing OpenSearch response:", str(e))

    results = []
    for r in hits:
        src = r.get("_source", {})
        results.append({
            "review_id": src.get("review_id", ""),
            "restaurant_name": src.get("restaurant_name") or src.get("location") or "Unknown",
            "rating": float(src.get("rating", 0)),
            "text": src.get("text", "")
        })

    print(f"[INFO] Found {len(results)} review matches.")

    # --- Build response (Bedrock Agent action group compatible) ---
    response_body = json.dumps({"results": results})

    # If this is a Bedrock Agent action group invocation, return agent-compatible format
    if "actionGroup" in event:
        return {
            "messageVersion": "1.0",
            "response": {
                "actionGroup": event.get("actionGroup", ""),
                "apiPath": event.get("apiPath", "/search"),
                "httpMethod": event.get("httpMethod", "POST"),
                "httpStatusCode": 200,
                "responseBody": {
                    "application/json": {
                        "body": response_body
                    }
                }
            }
        }

    # Direct invocation format
    return {
        "statusCode": 200,
        "body": response_body
    }
