"""
AWS Lambda handler for TasteTrend Analytics API.

This file is the Lambda entry point.
It wires together ETL, embeddings, and RAG components
to serve API requests via API Gateway.
"""

import json
from pathlib import Path

from src.etl import ReviewLoader, FileSpec, SYNONYMS
from src.utils.logger import get_logger

logger = get_logger(__name__)


def lambda_handler(event, context):
    """
    AWS Lambda entrypoint.
    Expects `event` from API Gateway (proxy integration).
    Routes requests to ETL, embeddings, or RAG components.
    """
    try:
        logger.info("Received event: %s", event)

        # Example: handle "etl" action
        action = event.get("action")
        if action == "etl":
            # (In production, you'd load files from S3, not local disk)
            spec = FileSpec(Path("/tmp/input.csv"), "api_upload")
            loader = ReviewLoader(SYNONYMS)
            df = loader.load_and_standardize(spec)

            return {
                "statusCode": 200,
                "body": json.dumps({"rows": len(df)})
            }

        # Default fallback
        return {
            "statusCode": 400,
            "body": json.dumps({"error": f"Unknown action: {action}"})
        }

    except Exception as e:
        logger.exception("Error in handler")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
