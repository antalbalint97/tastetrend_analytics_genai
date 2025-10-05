"""
AWS Lambda RAG Query Handler for TasteTrend Analytics.

Delegates to rag.test_query.search() to perform vector search in OpenSearch.
"""

import json
from utils.logger import get_logger
from rag.test_query import search

logger = get_logger(__name__)

def handle_rag_query(event, context):
    """
    Lambda wrapper for semantic search.
    Expected event:
      {
        "query": "What do customers like most about the Uptown location?",
        "filters": {"location": "Uptown"},
        "top_k": 6
      }
    """
    try:
        query = event.get("query")
        if not query:
            return {"statusCode": 400, "body": json.dumps({"error": "Missing 'query'"})}

        filters = event.get("filters", {})
        top_k = int(event.get("top_k", 6))
        results = search(query, k=top_k, filters=filters)

        return {"statusCode": 200, "body": json.dumps({"results": results}, indent=2)}

    except Exception as e:
        logger.error(f"Error during RAG query: {e}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
