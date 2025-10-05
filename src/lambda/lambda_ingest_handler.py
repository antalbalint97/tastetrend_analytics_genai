"""
AWS Lambda RAG Ingest Handler for TasteTrend Analytics.

Delegates to rag.ingest_parquet_to_opensearch for Bedrock + OpenSearch ingestion.
"""

import json
from utils.logger import get_logger
from rag.ingest_parquet_to_opensearch import main as rag_ingest_main

logger = get_logger(__name__)

def handle_rag_ingest(event, context):
    """Lambda wrapper for RAG ingestion."""
    try:
        logger.info("Invoking RAG ingestion via rag.ingest_parquet_to_opensearch.main()")
        rag_ingest_main()
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "RAG ingestion completed successfully"})
        }
    except Exception as e:
        logger.error(f"Error during RAG ingestion: {e}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
