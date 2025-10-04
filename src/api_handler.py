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

from etl import ReviewLoader, FileSpec, SYNONYMS, read_table_any
from utils.logger import get_logger
from etl_validation import validate_with_integrity, save_validation_report

logger = get_logger(__name__)
s3 = boto3.client("s3")


def lambda_handler(event, context):
    """
    AWS Lambda entrypoint.
    Expects `event` from API Gateway (proxy integration).

    Example payload:
    {
      "action": "etl",
      "bucket": "tastetrend-dev-raw-550744777598"
    }
    """
    try:
        logger.info("Received event: %s", event)

        action = event.get("action")
        if action == "etl":
            bucket = event.get("bucket")
            if not bucket:
                return {
                    "statusCode": 400,
                    "body": json.dumps({"error": "Missing 'bucket' in event"})
                }

            # 1. List all objects in the raw bucket
            resp = s3.list_objects_v2(Bucket=bucket)
            if "Contents" not in resp:
                return {
                    "statusCode": 404,
                    "body": json.dumps({"error": "No files found in bucket"})
                }

            account_id = context.invoked_function_arn.split(":")[4]
            processed_bucket = f"tastetrend-dev-processed-{account_id}"

            loader = ReviewLoader(SYNONYMS)
            all_data = []
            processed_files = []

            for obj in resp["Contents"]:
                key = obj["Key"]
                if not (key.endswith(".csv") or key.endswith(".txt")):
                    continue  # skip non-data files

                # 2. Download raw file
                local_path = Path("/tmp") / Path(key).name
                logger.info("Downloading s3://%s/%s -> %s", bucket, key, local_path)
                s3.download_file(bucket, key, str(local_path))

                # Count raw rows
                try:
                    df_raw = read_table_any(local_path)
                except Exception as e:
                    logger.error("Failed to read raw file %s: %s", key, e)
                    continue

                # 3. Run ETL
                spec = FileSpec(local_path, key)
                df_processed = loader.load_and_standardize(spec)
                logger.info("ETL complete for %s: %s rows", key, len(df_processed))

                # 4. Save processed parquet locally + upload
                processed_local = Path("/tmp") / f"processed_{local_path.stem}.parquet"
                df_processed.to_parquet(processed_local, index=False)

                processed_key = f"processed/{processed_local.name}"
                logger.info("Uploading processed file to s3://%s/%s", processed_bucket, processed_key)
                s3.upload_file(str(processed_local), processed_bucket, processed_key)

                processed_files.append(processed_key)

                # Add to validation input
                all_data.append((df_raw, df_processed, key))

            # 5. Run combined validation across all datasets
            validation_report = validate_with_integrity(all_data, context=context)

            # Save + upload combined validation report
            validation_local = Path("/tmp/validation_combined.json")
            save_validation_report(validation_report, validation_local)
            validation_key = "processed/validation_combined.json"
            s3.upload_file(str(validation_local), processed_bucket, validation_key)
            logger.info("Validation report uploaded to s3://%s/%s", processed_bucket, validation_key)

            # 6. Response body
            response_body = {
                "processed_files": processed_files,
                "validation_file": validation_key,
                "processed_bucket": processed_bucket,
                "validation_summary": {
                    "status": validation_report.get("status"),
                    "sources": [
                        {
                            "source": s.get("source"),
                            "status": s.get("status"),
                            "row_count_raw": s.get("row_count_raw"),
                            "row_count_processed": s.get("row_count_processed"),
                            "warnings": s.get("warnings", {})
                        }
                        for s in validation_report.get("sources", [])
                    ]
                }
            }

            return {
                "statusCode": 200,
                "body": json.dumps(response_body)
            }

        # Fallback if action not recognized
        return {
            "statusCode": 400,
            "body": json.dumps({"error": f"Unknown action: {action}"} )
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