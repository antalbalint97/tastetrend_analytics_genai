"""
AWS Lambda RAG Ingest Handler for TasteTrend Analytics.

Note:
    For this PoC, ingestion was performed manually via EC2 using:
        PYTHONPATH=src python3 -m rag.ingest_parquet_to_opensearch

    The Lambda entrypoint is kept for completeness, but is not invoked in production.
"""

import json
from utils.logger import get_logger

logger = get_logger(__name__)

def handle_rag_ingest(event, context):
    """Placeholder for RAG ingestion (disabled in PoC)."""
    logger.info("RAG ingestion handler invoked, but ingestion was executed manually on EC2.")
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Ingestion already completed manually on EC2. "
                       "No action required for this Lambda path."
        })
    }
