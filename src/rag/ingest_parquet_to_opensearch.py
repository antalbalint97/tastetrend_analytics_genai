import os
import json
import boto3
import awswrangler as wr
import pandas as pd
from opensearchpy import OpenSearch, RequestsHttpConnection, helpers
from requests_aws4auth import AWS4Auth
from rag.chunker import chunk_text

import time, random, itertools
from concurrent.futures import ThreadPoolExecutor, as_completed
import botocore

# --- Configuration ---
REGION = os.environ["AWS_REGION"]
OS_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]
OS_INDEX = os.environ.get("OS_INDEX", "reviews_v1")
BEDROCK_EMBED_MODEL = os.environ.get("BEDROCK_EMBED_MODEL", "amazon.titan-embed-text-v2:0")

S3_URI = os.environ.get(
    "PROCESSED_S3_URI",
    "s3://tastetrend-dev-processed-550744777598/processed/processed_final.parquet"
)

TEXT_COL = os.environ.get("TEXT_COL", "review_text")

MAX_WORKERS = int(os.environ.get("EMBED_WORKERS", "16"))
RETRY_ATTEMPTS = 5

# --- AWS Sessions & Auth ---
session = boto3.Session(region_name=REGION)
credentials = session.get_credentials().get_frozen_credentials()

# Use AWS4Auth for signing OpenSearch Serverless ("aoss") requests
awsauth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    REGION,
    "aoss",  # Service name for OpenSearch Serverless
    session_token=credentials.token,
)

# Normalize domain host
host = OS_ENDPOINT.replace("https://", "").replace("http://", "").split("/")[0]

# --- OpenSearch Client ---
es = OpenSearch(
    hosts=[{"host": host, "port": 443}],
    http_auth=awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)

# --- Bedrock Client (for embeddings) ---
bedrock = session.client("bedrock-runtime", region_name=REGION)

# --- Embedding Helpers ---
def embed_one(text: str):
    """Embed a single text chunk with retry + exponential backoff."""
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
            # small jittered backoff for unknown transient errors
            time.sleep(min(5, 0.2 * attempt) + random.random() * 0.1)
    raise RuntimeError("Failed to embed after retries")

def embed_parallel(texts):
    """Parallel embedding using ThreadPoolExecutor."""
    vectors = [None] * len(texts)
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(embed_one, t): i for i, t in enumerate(texts)}
        for fut in as_completed(futures):
            i = futures[fut]
            vectors[i] = fut.result()
    return vectors

# --- Indexing Helper ---
def make_actions(df_iter, batch_chunks=64):
    """Yield OpenSearch index actions for each text chunk and embedding."""
    for _, row in df_iter:
        text = row.get(TEXT_COL) or ""
        chunks = chunk_text(text, target_chars=1200, overlap=240)

        meta = {
            "review_id": row.get("review_id"),
            "location": row.get("location"),
            "menu_item": row.get("menu_item"),
            "rating": float(row.get("rating")) if row.get("rating") is not None else None,
            "sentiment": row.get("sentiment"),
            "ts": row.get("ts")
        }

        # process chunks in manageable batches
        for i in range(0, len(chunks), batch_chunks):
            batch = chunks[i:i + batch_chunks]
            vectors = embed_parallel(batch)
            for ch, vec in zip(batch, vectors):
                yield {
                    "_op_type": "index",
                    "_index": OS_INDEX,
                    "_source": {
                        "vector": vec,
                        "chunk_text": ch,
                        **meta
                    }
                }

# --- Main Ingestion Flow ---
def main():
    print(f"Reading processed dataset from: {S3_URI}")
    if S3_URI.startswith("s3://"):
        df = wr.s3.read_parquet(S3_URI)
    else:
        df = pd.read_parquet(S3_URI)

    # Filter out empty or null text
    df = df[df[TEXT_COL].notna() & (df[TEXT_COL].str.len() > 0)]
    total_reviews = len(df)
    print(f"Loaded {total_reviews} reviews. Starting embedding and indexing...")

    # Stagger start to avoid burst throttling
    time.sleep(random.random())

    actions = make_actions(df.iterrows(), batch_chunks=64)

    success_total, failed_total = 0, 0
    chunk_counter = 0
    print("Beginning bulk ingestion to OpenSearch...")

    for ok, item in helpers.streaming_bulk(
        es,
        actions,
        chunk_size=500,
        max_retries=3,
        request_timeout=120
    ):
        chunk_counter += 1
        if ok:
            success_total += 1
        else:
            failed_total += 1
        if chunk_counter % 500 == 0:
            print(f"Progress: {chunk_counter} chunks processed ({success_total} indexed, {failed_total} failed)")

    print(f"--- Ingestion complete ---")
    print(f"Indexed: {success_total} | Failed: {failed_total}")

# --- Entrypoint ---
if __name__ == "__main__":
    main()