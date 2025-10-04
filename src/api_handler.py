"""
AWS Lambda handler for TasteTrend Analytics API.

This file is the Lambda entry point.
It wires together ETL, embeddings, and RAG components
to serve API requests via API Gateway.
"""

import json
import boto3
from pathlib import Path
import traceback

from etl import ReviewLoader, FileSpec, SYNONYMS
from utils.logger import get_logger

logger = get_logger(__name__)
s3 = boto3.client("s3")


def lambda_handler(event, context):
    """
    AWS Lambda entrypoint.
    Expects `event` from API Gateway (proxy integration).
    Routes requests to ETL, embeddings, or RAG components.

    Example payload:
    {
      "action": "etl",
      "bucket": "tastetrend-dev-raw-550744777598",
      "key": "tastetrend_downtown_reviews.csv"
    }
    """
    try:
        logger.info("Received event: %s", event)

        action = event.get("action")
        if action == "etl":
            bucket = event.get("bucket")
            key = event.get("key")

            if not bucket or not key:
                return {
                    "statusCode": 400,
                    "body": json.dumps({"error": "Missing 'bucket' or 'key' in event"})
                }

            # 1. Download raw file into /tmp
            local_path = Path("/tmp") / Path(key).name
            logger.info("Downloading s3://%s/%s -> %s", bucket, key, local_path)
            s3.download_file(bucket, key, str(local_path))

            # 2. Run ETL
            spec = FileSpec(local_path, key)
            loader = ReviewLoader(SYNONYMS)
            df = loader.load_and_standardize(spec)
            logger.info("ETL complete: %s rows standardized", len(df))

            # 3. Save processed file locally
            processed_local = Path("/tmp") / f"processed_{local_path.stem}.parquet"
            df.to_parquet(processed_local, index=False)
            logger.info("Processed file written to %s", processed_local)

            # 4. Upload processed file to processed bucket
            account_id = context.invoked_function_arn.split(":")[4]
            processed_bucket = f"tastetrend-dev-processed-{account_id}"
            processed_key = f"processed/{processed_local.name}"
            logger.info("Uploading %s -> s3://%s/%s", processed_local, processed_bucket, processed_key)
            s3.upload_file(str(processed_local), processed_bucket, processed_key)

            return {
                "statusCode": 200,
                "body": json.dumps({
                    "rows": len(df),
                    "raw_file": key,
                    "processed_file": processed_key,
                    "processed_bucket": processed_bucket
                })
            }

        # Fallback if action not recognized
        return {
            "statusCode": 400,
            "body": json.dumps({"error": f"Unknown action: {action}"})
        }

    except Exception as e:
        logger.error("Exception in lambda_handler: %s", str(e))
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": str(e),
                "traceback": traceback.format_exc()
            })
        }
