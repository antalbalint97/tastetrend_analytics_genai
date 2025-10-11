"""
TasteTrend Analytics — Local RAG Query Lambda (optional)
NOT used by the production path once Bedrock Agent + Proxy is in place.
Useful for quick OpenSearch checks.
"""

import json
from utils.logger import get_logger
from rag.test_query import search  # your existing local search helper

logger = get_logger(__name__)

def handler(event, context):
    try:
        query = event.get("query")
        if not query:
            return {"statusCode": 400, "body": json.dumps({"error": "Missing 'query'"})}

        filters = event.get("filters", {})
        top_k   = int(event.get("top_k", 6))
        results = search(query, k=top_k, filters=filters)

        return {"statusCode": 200, "body": json.dumps({"results": results}, indent=2)}
    except Exception as e:
        logger.error("RAG query error: %s", e, exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
