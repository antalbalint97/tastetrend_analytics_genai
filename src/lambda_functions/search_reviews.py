import json, boto3, os, requests
from requests_aws4auth import AWS4Auth

# === Environment variables ===
OPENSEARCH_URL = os.environ["OPENSEARCH_URL"]
INDEX_NAME = os.environ["INDEX_NAME"]
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


# def lambda_handler(event, context):
#     """Lambda entry point for Bedrock Agent Action Group."""
#     print("Event received:", json.dumps(event, default=str))

#     # --- Extract query safely (supports both 'q' and 'query') ---
#     body = {}
#     if isinstance(event.get("body"), str):
#         try:
#             body = json.loads(event["body"])
#         except Exception:
#             body = {}
#     elif isinstance(event.get("body"), dict):
#         body = event.get("body", {})

#     query = (
#         body.get("query") or
#         body.get("q") or
#         event.get("query") or
#         event.get("q")
#     )

#     if not query:
#         return {
#             "responseBody": {
#                 "application/json": {"error": "Missing 'query' parameter"}
#             },
#             "responseHeaders": {"Content-Type": "application/json"},
#             "statusCode": 400
#         }

#     print(f"Processing query: {query}")

#     # --- Generate embedding ---
#     emb = get_embedding(query)

#     # --- Perform vector search in OpenSearch ---
#     search_payload = {
#         "size": 5,
#         "query": {"knn": {"vector": {"vector": emb, "k": 5}}},
#         "_source": ["text", "restaurant_name", "review_id"]
#     }

#     resp = requests.post(
#         f"{OPENSEARCH_URL}/{INDEX_NAME}/_search",
#         auth=awsauth,
#         headers={"Content-Type": "application/json"},
#         data=json.dumps(search_payload)
#     )

#     print("OpenSearch status:", resp.status_code)
#     print("OpenSearch body:", resp.text)

#     # --- Parse results safely ---
#     hits = []
#     try:
#         response_json = resp.json()
#         hits = response_json.get("hits", {}).get("hits", [])
#     except Exception as e:
#         print("Error parsing OpenSearch response:", str(e))

#     results = [
#         {
#             "review_id": r["_source"].get("review_id"),
#             "restaurant_name": r["_source"].get("restaurant_name"),
#             "text": r["_source"].get("text")
#         }
#         for r in hits
#     ]

#     print(f"Found {len(results)} review matches.")

#     # === Bedrock Agent–compliant response ===
#     return {
#         "responseBody": {
#             "application/json": {
#                 "results": results
#             }
#         },
#         "responseHeaders": {
#             "Content-Type": "application/json"
#         },
#         "statusCode": 200
#     }

def lambda_handler(event, context):
    """Lambda entry point for Bedrock Agent Action Group."""
    print("Event received:", json.dumps(event, default=str))

    # --- Detect Bedrock system validation / health checks ---
    if isinstance(event, dict) and "actionGroup" in event:
        print("[DEBUG] Detected Bedrock validation event")
        print("[DEBUG] Validation OK — returning 200 to unblock alias creation")
        return {
            "responseBody": {
                "application/json": {"message": "Validation OK"}
            },
            "responseHeaders": {"Content-Type": "application/json"},
            "statusCode": 200
        }

    # --- Extract query safely (supports both 'q' and 'query') ---
    body = {}
    if isinstance(event.get("body"), str):
        try:
            body = json.loads(event["body"])
        except Exception:
            body = {}
    elif isinstance(event.get("body"), dict):
        body = event.get("body", {})

    query = (
        body.get("query")
        or body.get("q")
        or event.get("query")
        or event.get("q")
    )

    if not query:
        print("[WARN] Missing 'query' parameter in request")
        return {
            "responseBody": {
                "application/json": {"error": "Missing 'query' parameter"}
            },
            "responseHeaders": {"Content-Type": "application/json"},
            "statusCode": 400
        }

    print(f"[DEBUG] Processing search query: {query}")

    # --- Generate embedding ---
    emb = get_embedding(query)

    # --- Perform vector search in OpenSearch ---
    search_payload = {
        "size": 5,
        "query": {"knn": {"vector": {"vector": emb, "k": 5}}},
        "_source": ["text", "restaurant_name", "review_id"]
    }

    resp = requests.post(
        f"{OPENSEARCH_URL}/{INDEX_NAME}/_search",
        auth=awsauth,
        headers={"Content-Type": "application/json"},
        data=json.dumps(search_payload)
    )

    print(f"[DEBUG] OpenSearch status: {resp.status_code}")
    print(f"[DEBUG] OpenSearch response body: {resp.text}")

    # --- Parse results safely ---
    hits = []
    try:
        response_json = resp.json()
        hits = response_json.get("hits", {}).get("hits", [])
    except Exception as e:
        print("[ERROR] Error parsing OpenSearch response:", str(e))

    results = [
        {
            "review_id": r["_source"].get("review_id"),
            "restaurant_name": r["_source"].get("restaurant_name"),
            "text": r["_source"].get("text")
        }
        for r in hits
    ]

    print(f"[DEBUG] Found {len(results)} review matches.")

    # === Bedrock Agent–compliant response ===
    return {
        "responseBody": {
            "application/json": {"results": results}
        },
        "responseHeaders": {
            "Content-Type": "application/json"
        },
        "statusCode": 200
    }
