"""
Unified TasteTrend Analytics API Lambda Handler.

This Lambda serves as the central entry point for TasteTrend’s analytics workflow:
- action="etl"         → Runs the ETL pipeline (raw → processed)
- action="rag_ingest"  → Embeds processed data into OpenSearch
- action="rag_query"   → Performs semantic RAG search over indexed data
"""

import sys
import pkg_resources

def lambda_handler(event, context):
    print("=== Layer Paths ===")
    print("\n".join(sys.path))
    print("\n=== Installed Packages ===")
    installed = [p.key for p in pkg_resources.working_set if "s3fs" in p.key or "pandas" in p.key]
    print(installed)
    return {"status": "ok", "found_packages": installed}


import json
import traceback
from utils.logger import get_logger

# Import modular handlers
from .lambda_etl_handler import handle_etl
from .lambda_ingest_handler import handle_rag_ingest
from .lambda_query_handler import handle_rag_query

logger = get_logger(__name__)


def lambda_handler(event, context):
    """
    AWS Lambda entrypoint.

    Expected event format (examples):
    ---------------------------------
    {
        "action": "etl",
        "bucket": "tastetrend-dev-raw-1234567890"
    }

    {
        "action": "rag_ingest",
        "text": "Amazing tiramisu at Uptown Café",
        "id": "review_1024"
    }

    {
        "action": "rag_query",
        "query": "What desserts do people love at Uptown?"
    }
    """
    try:
        if not isinstance(event, dict):
            logger.error("Invalid event type: %s", type(event))
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Invalid request: event must be a JSON object"})
            }

        action = event.get("action")
        logger.info(f"[TasteTrend API] Received action: {action}")

        if action == "etl":
            return handle_etl(event, context)

        elif action == "rag_ingest":
            return handle_rag_ingest(event, context)

        elif action == "rag_query":
            return handle_rag_query(event, context)

        else:
            logger.warning("Unknown action requested: %s", action)
            return {
                "statusCode": 400,
                "body": json.dumps({"error": f"Unknown action '{action}'"})
            }

    except Exception as e:
        logger.error("Unhandled error in lambda_handler: %s", str(e))
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": str(e),
                "traceback": traceback.format_exc()
            })
        }
