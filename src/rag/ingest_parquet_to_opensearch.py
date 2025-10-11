import os
import json
import boto3
import awswrangler as wr
import pandas as pd
from opensearchpy import OpenSearch, RequestsHttpConnection, helpers
from requests_aws4auth import AWS4Auth
from rag.chunker import chunk_text
import time
import random
from concurrent.futures import ThreadPoolExecutor, as_completed
import botocore

# ---------------------------
# Configuration
# ---------------------------
REGION = os.environ["AWS_REGION"]
OS_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]
OS_INDEX = os.environ.get("OS_INDEX", "reviews_v1")
BEDROCK_EMBED_MODEL = os.environ.get("BEDROCK_EMBED_MODEL", "amazon.titan-embed-text-v2:0")

# Default S3 path (used for EC2/manual runs)
DEFAULT_S3_URI = os.environ.get(
    "PROCESSED_S3_URI",
    "s3://tastetrend-dev-processed-550744777598/processed/processed_final.parquet"
)

TEXT_COL = os.environ.get("TEXT_COL", "review_text")
MAX_WORKERS = int(os.environ.get("EMBED_WORKERS", "16"))
RETRY_ATTEMPTS = 5

# ---------------------------
# AWS Setup
# ---------------------------
session = boto3.Session(region_name=REGION)
credentials = session.get_credentials().get_frozen_credentials()

awsauth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    REGION,
    "aoss",  # service name for OpenSearch Serverless
    session_token=credentials.token,
)

# Normalize endpoint
host = OS_ENDPOINT.replace("https://", "").replace("http://", "").split("/")[0]

# OpenSearch client
es = OpenSearch(
    hosts=[{"host": host, "port": 443}],
    http_auth=awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)

# Bedrock client
bedrock = session.client("bedrock-runtime", region_name=REGION)


# ---------------------------
# Embedding Helpers
# ---------------------------
def embed_one(text: str):
    """Embed one text chunk with exponential backoff."""
    payload = {"inputText": text, "dimensions": 1024, "normalize": True}
    for attempt in range(1, RETRY_ATTEMPTS + 1):
        try:
            resp = bedrock.invoke_model(
                modelId=BEDROCK_EMBED_MODEL,
                body=json.dumps(payload)
            )
            out = json.loads(resp["body"].read())
            return out["embedding"]

        except botocore.exceptions.ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            status = e.response["ResponseMetadata"]["HTTPStatusCode"]
            if code in ("ThrottlingException", "TooManyRequestsException") or status >= 500:
                sleep = min(10, 0.25 * (2 ** (attempt - 1))) + random.random() * 0.25
                time.sleep(sleep)
                continue
            raise
        except Exception:
            time.sleep(min(5, 0.2 * attempt) + random.random() * 0.1)
    raise RuntimeError("Failed to embed after retries")


def embed_parallel(texts):
    """Parallel embedding using threads."""
    vectors = [None] * len(texts)
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(embed_one, t): i for i, t in enumerate(texts)}
        for fut in as_completed(futures):
            i = futures[fut]
            try:
                vectors[i] = fut.result()
            except Exception as e:
                print(f"[WARN] Failed to embed text {i}: {e}")
                vectors[i] = None
    return vectors


# ---------------------------
# Indexing Helpers
# ---------------------------
def make_actions(df_iter, batch_chunks=64):
    """Yield OpenSearch index actions for each text chunk and embedding."""
    for _, row in df_iter:
        text = row.get(TEXT_COL) or ""
        if not text:
            continue

        chunks = chunk_text(text, target_chars=1200, overlap=240)
        meta = {
            "review_id": row.get("review_id"),
            "location": row.get("location"),
            "menu_item": row.get("menu_item"),
            "rating": float(row.get("rating")) if row.get("rating") is not None else None,
            "sentiment": row.get("sentiment"),
            "ts": row.get("ts"),
        }

        # Process in sub-batches for throttling protection
        for i in range(0, len(chunks), batch_chunks):
            batch = chunks[i:i + batch_chunks]
            vectors = embed_parallel(batch)
            for ch, vec in zip(batch, vectors):
                if vec is None:
                    continue
                yield {
                    "_op_type": "index",
                    "_index": OS_INDEX,
                    "_source": {
                        "vector": vec,
                        "chunk_text": ch,
                        **meta
                    }
                }


# ---------------------------
# Ingestion Core
# ---------------------------
def ingest_to_opensearch(s3_uri: str):
    """Core logic for ingestion (shared by EC2 and Lambda)."""
    print(f"Reading processed dataset from: {s3_uri}")
    if s3_uri.startswith("s3://"):
        df = wr.s3.read_parquet(s3_uri)
    else:
        df = pd.read_parquet(s3_uri)

    df = df[df[TEXT_COL].notna() & (df[TEXT_COL].str.len() > 0)]
    total_reviews = len(df)
    print(f"Loaded {total_reviews} reviews. Starting embedding and indexing...")

    time.sleep(random.random())  # stagger start for throttling
    actions = make_actions(df.iterrows(), batch_chunks=64)

    success_total, failed_total = 0, 0
    print("Beginning bulk ingestion to OpenSearch...")

    for ok, item in helpers.streaming_bulk(
        es,
        actions,
        chunk_size=500,
        max_retries=3,
        request_timeout=120
    ):
        if ok:
            success_total += 1
        else:
            failed_total += 1

    print(f"--- Ingestion complete ---")
    print(f"Indexed: {success_total} | Failed: {failed_total}")


# ---------------------------
# Entry Points
# ---------------------------
def lambda_handler(event, context):
    """Lambda entrypoint — can be called from Step Functions."""
    try:
        s3_uri = event.get("s3_batch_uri", DEFAULT_S3_URI)
        print(f"[Lambda] Starting ingestion for: {s3_uri}")
        ingest_to_opensearch(s3_uri)
        return {"statusCode": 200, "body": json.dumps({"status": "ok", "s3_batch_uri": s3_uri})}
    except Exception as e:
        print(f"[ERROR] Lambda ingestion failed: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def main():
    """CLI / EC2 entrypoint."""
    print("[EC2] Starting full ingestion job...")
    ingest_to_opensearch(DEFAULT_S3_URI)


# ---------------------------
# Execution Guard
# ---------------------------
if __name__ == "__main__":
    main()
