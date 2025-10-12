import json, boto3, os, requests

OPENSEARCH_URL = os.environ["OPENSEARCH_URL"]
INDEX_NAME = os.environ["INDEX_NAME"]
MODEL_ID = "amazon.titan-embed-text-v2:0"

bedrock = boto3.client("bedrock-runtime")
session = boto3.Session()
http = requests.Session()

def get_embedding(query):
    resp = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps({"inputText": query}),
        accept="application/json",
        contentType="application/json"
    )
    payload = json.loads(resp["body"].read())
    return payload["embedding"]

def lambda_handler(event, context):
    query = event.get("query") or event["body"].get("query")
    emb = get_embedding(query)
    
    # OpenSearch vector search
    resp = http.post(
        f"{OPENSEARCH_URL}/{INDEX_NAME}/_search",
        headers={"Content-Type": "application/json"},
        data=json.dumps({
            "size": 5,
            "query": {
                "knn": {"embedding": {"vector": emb, "k": 5}}
            },
            "_source": ["text", "restaurant_name", "review_id"]
        })
    )
    results = resp.json()["hits"]["hits"]
    return {
        "results": [
            {
                "text": r["_source"]["text"],
                "restaurant": r["_source"].get("restaurant_name"),
                "review_id": r["_source"]["review_id"]
            }
            for r in results
        ]
    }
