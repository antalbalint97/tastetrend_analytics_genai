"""
AWS Lambda ETL Handler for TasteTrend Analytics

This Lambda performs the raw → processed transformation step:
1. Reads all raw review files from the raw S3 bucket.
2. Runs the ETL pipeline via ReviewLoader.
3. Validates and combines outputs.
4. Uploads processed parquet + validation + bias summary to the processed bucket.
"""

import json
import boto3
import traceback
import pandas as pd
from pathlib import Path

from etl.etl import ReviewLoader, FileSpec, SYNONYMS, read_table_any
from etl.etl_validation import validate_with_integrity, save_validation_report
from utils.logger import get_logger

logger = get_logger(__name__)
s3 = boto3.client("s3")


# -------------------------------------------------------------
# Utility: safe_json_dict
# -------------------------------------------------------------
def safe_json_dict(d: dict) -> dict:
    """Convert keys to strings and replace NaN/NA keys with 'NA'."""
    clean = {}
    for k, v in d.items():
        if pd.isna(k):
            clean["NA"] = v
        else:
            clean[str(k)] = v
    return clean


# -------------------------------------------------------------
# Lambda Handler
# -------------------------------------------------------------
def handle_etl(event, context):
    """
    Lambda ETL entrypoint.

    Expected event example:
    {
      "bucket": "tastetrend-dev-raw-550744777598"
    }
    """
    try:
        logger.info("Received ETL event: %s", event)

        bucket = event.get("bucket")
        if not bucket:
            return {"statusCode": 400, "body": json.dumps({"error": "Missing 'bucket' field"})}

        # 1. List raw files in bucket
        resp = s3.list_objects_v2(Bucket=bucket)
        if "Contents" not in resp:
            return {"statusCode": 404, "body": json.dumps({"error": "No files found in bucket"})}

        account_id = context.invoked_function_arn.split(":")[4]
        processed_bucket = f"tastetrend-dev-processed-{account_id}"

        loader = ReviewLoader(SYNONYMS)
        all_data = []
        processed_files = []

        # -------------------------------------------------------------
        # 2. Iterate through raw files
        # -------------------------------------------------------------
        for obj in resp["Contents"]:
            key = obj["Key"]
            if not (key.endswith(".csv") or key.endswith(".txt")):
                continue  # Skip non-data files

            local_path = Path("/tmp") / Path(key).name
            logger.info("Downloading s3://%s/%s -> %s", bucket, key, local_path)
            s3.download_file(bucket, key, str(local_path))

            try:
                df_raw = read_table_any(local_path)
            except Exception as e:
                logger.error("Failed to read raw file %s: %s", key, e)
                continue

            # 3. Run ETL
            spec = FileSpec(local_path, key)
            df_processed = loader.load_and_standardize(spec)
            logger.info("ETL complete for %s: %s rows", key, len(df_processed))

            # 4. Upload processed parquet
            processed_local = Path("/tmp") / f"processed_{local_path.stem}.parquet"
            df_processed.to_parquet(processed_local, index=False)
            processed_key = f"processed/{processed_local.name}"

            logger.info("Uploading processed file to s3://%s/%s", processed_bucket, processed_key)
            s3.upload_file(str(processed_local), processed_bucket, processed_key)

            processed_files.append(processed_key)
            all_data.append((df_raw, df_processed, key))

        if not all_data:
            return {"statusCode": 404, "body": json.dumps({"error": "No valid data files found"})}

        # -------------------------------------------------------------
        # 5. Validation
        # -------------------------------------------------------------
        validation_report = validate_with_integrity(all_data, context=context)

        validation_local = Path("/tmp/validation_combined.json")
        save_validation_report(validation_report, validation_local)
        validation_key = "processed/validation_combined.json"
        s3.upload_file(str(validation_local), processed_bucket, validation_key)
        logger.info("Validation report uploaded to s3://%s/%s", processed_bucket, validation_key)

        # -------------------------------------------------------------
        # 6. Combine processed data
        # -------------------------------------------------------------
        logger.info("Combining all processed DataFrames into one...")
        combined_df = pd.concat(
            [df_processed for _, df_processed, _ in all_data],
            ignore_index=True
        )
        combined_df["review_id"] = range(1, len(combined_df) + 1)

        combined_local = Path("/tmp/processed_final.parquet")
        combined_df.to_parquet(combined_local, index=False)
        combined_key = "processed/processed_final.parquet"
        s3.upload_file(str(combined_local), processed_bucket, combined_key)
        logger.info("Uploaded combined final dataset to s3://%s/%s", processed_bucket, combined_key)

        # -------------------------------------------------------------
        # 7. Bias Summary
        # -------------------------------------------------------------
        bias_summary = {}
        for col in ["gender_norm", "age_group", "ethnicity_norm"]:
            if col in combined_df.columns:
                counts = combined_df[col].value_counts(dropna=False).to_dict()
                counts = safe_json_dict(counts)
                missing_pct = float(combined_df[col].isna().mean() * 100)
                bias_summary[col] = {
                    "counts": counts,
                    "missing_pct": round(missing_pct, 2)
                }
                logger.info("[BIAS SUMMARY] %s: %s (Missing: %.2f%%)", col, counts, missing_pct)

        bias_local = Path("/tmp/bias_summary.json")
        with open(bias_local, "w", encoding="utf-8") as f:
            json.dump(bias_summary, f, indent=2)

        bias_key = "processed/bias_summary.json"
        s3.upload_file(str(bias_local), processed_bucket, bias_key)
        logger.info("Uploaded bias summary to s3://%s/%s", processed_bucket, bias_key)

        # -------------------------------------------------------------
        # 8. Response
        # -------------------------------------------------------------
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
                        "warnings": s.get("warnings", {}),
                    }
                    for s in validation_report.get("sources", [])
                ],
            },
        }

        return {"statusCode": 200, "body": json.dumps(response_body)}

    except Exception as e:
        logger.error("Exception in handle_etl: %s", str(e))
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e), "traceback": traceback.format_exc()}),
        }
