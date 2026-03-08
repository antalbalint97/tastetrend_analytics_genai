import json
import boto3
import os
import re
import requests
from requests_aws4auth import AWS4Auth

# === Environment variables ===
OPENSEARCH_URL = os.environ["OPENSEARCH_URL"]
INDEX_NAME = os.environ.get("INDEX_NAME", "reviews")
MODEL_ID = "amazon.titan-embed-text-v2:0"
REGION = os.environ.get("AWS_REGION", "eu-central-1")

# Known restaurant / location names for metadata-aware filtering.
# Extend via the KNOWN_LOCATIONS env var (comma-separated).
# Casing must match the `restaurant_name` keyword values stored in OpenSearch.
_DEFAULT_LOCATIONS = ["Riverside", "Uptown", "Downtown", "Midtown", "Lakeside"]
KNOWN_LOCATIONS = [
    loc.strip()
    for loc in os.environ.get(
        "KNOWN_LOCATIONS", ",".join(_DEFAULT_LOCATIONS)
    ).split(",")
    if loc.strip()
]

# Pre-compile word-boundary patterns for each known location (case-insensitive).
_LOCATION_PATTERNS = {
    loc: re.compile(r'\b' + re.escape(loc) + r'\b', re.IGNORECASE)
    for loc in KNOWN_LOCATIONS
}

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


def _detect_location(query: str):
    """Return the first known location mentioned in *query*, or ``None``.

    Matching is case-insensitive with word boundaries.  The returned string
    preserves the original casing from ``KNOWN_LOCATIONS`` so it can be used
    directly in an OpenSearch ``term`` filter against the ``restaurant_name``
    keyword field.
    """
    for loc, pattern in _LOCATION_PATTERNS.items():
        if pattern.search(query):
            return loc
    return None


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

    # --- Detect location for metadata filtering ---
    location = _detect_location(query)
    if location:
        print(f"[INFO] Detected location filter: {location}")

    # --- Generate embedding ---
    emb = get_embedding(query)

    # --- Build OpenSearch query: filtered KNN when a location is detected ---
    knn_body = {"vector": emb, "k": 5}
    if location:
        knn_body["filter"] = {"term": {"restaurant_name": location}}

    search_payload = {
        "size": 5,
        "query": {"knn": {"embedding": knn_body}},
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
        try:
            rating = float(src.get("rating", 0))
        except (ValueError, TypeError):
            rating = 0.0
        results.append({
            "review_id": src.get("review_id", ""),
            "restaurant_name": src.get("restaurant_name") or src.get("location") or "Unknown",
            "rating": rating,
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
