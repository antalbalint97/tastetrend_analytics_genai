"""
TasteTrend Analytics — ETL Lambda (batch)
- Runs the raw -> processed transformation
- Optionally triggers the embedding Lambda when ETL completes

Event examples:
  { "action": "etl", "bucket": "tastetrend-dev-raw-123456789012" }
  { "action": "etl", "bucket": "...", "trigger_embedding": true, "os_index": "reviews_v1" }
"""

import json
import boto3
import traceback
from utils.logger import get_logger
import os

# reuse your existing ETL implementation
from etl_core import handle_etl as _run_etl

logger = get_logger(__name__)
lambda_client = boto3.client("lambda")


def handler(event, context):
    try:
        if not isinstance(event, dict):
            return {"statusCode": 400, "body": json.dumps({"error": "Event must be a JSON object"})}

        action = event.get("action")
        if action and action != "etl":
            return {"statusCode": 400, "body": json.dumps({"error": f"Unsupported action '{action}'. Use 'etl'."})}

        # 1) Run ETL with your existing function
        etl_resp = _run_etl(event, context)
        if isinstance(etl_resp, dict) and etl_resp.get("statusCode", 200) >= 400:
            return etl_resp

        body = json.loads(etl_resp["body"]) if isinstance(etl_resp.get("body"), str) else etl_resp.get("body", {})

        # 2) Optionally trigger the embedding job (async) after ETL
        if event.get("trigger_embedding"):
            processed_bucket = body.get("processed_bucket")
            parquet_key      = "processed/processed_final.parquet"
            os_index         = event.get("os_index", "reviews_v1")

            if not processed_bucket:
                return {"statusCode": 500, "body": json.dumps({"error": "Missing processed_bucket from ETL result"})}

            invoke_payload = {
                "s3_parquet_uri": f"s3://{processed_bucket}/{parquet_key}",
                "os_index": os_index
            }

            logger.info("[Orchestrator] Invoking embedding Lambda with %s", invoke_payload)

            lambda_client.invoke(
                FunctionName = os.environ.get("EMBEDDING_LAMBDA_ARN") or os.environ.get("EMBEDDING_LAMBDA_NAME"),
                InvocationType = "Event",  # async
                Payload = json.dumps(invoke_payload).encode("utf-8")
            )

            body["embedding_triggered"] = True
            body["embedding_index"]     = os_index

        return {"statusCode": 200, "body": json.dumps(body)}

    except Exception as e:
        logger.error("ETL handler exception: %s", e, exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e), "traceback": traceback.format_exc()})}
