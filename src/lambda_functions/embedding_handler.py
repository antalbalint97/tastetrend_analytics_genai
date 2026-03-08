"""
TasteTrend Analytics — Embedding Lambda (batch)
- Reads processed reviews
- Generates Titan embeddings on Bedrock
- Upserts vectors into managed OpenSearch domain
"""

import os
import io
import json
import boto3
import csv
import time
from opensearchpy.helpers import bulk
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth

# --- Env ---
AWS_REGION  = os.getenv("AWS_REGION", "eu-central-1")
OS_ENDPOINT = os.environ["OS_ENDPOINT"]
DEFAULT_IDX = os.getenv("OS_INDEX", "reviews")

# --- Clients ---
session     = boto3.Session(region_name=AWS_REGION)
creds       = session.get_credentials()
auth        = AWSV4SignerAuth(creds, AWS_REGION, "es")
s3          = session.client("s3")
bedrock_rt  = session.client("bedrock-runtime", region_name=AWS_REGION)

os_client = OpenSearch(
    hosts=[{"host": OS_ENDPOINT, "port": 443}],
    http_auth=auth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
    timeout=60,
    max_retries=3,
    retry_on_timeout=True,
)


EMBED_MODEL = "amazon.titan-embed-text-v2:0"
VECTOR_DIM  = int(os.getenv("VECTOR_DIM", "1536"))
BATCH       = int(os.getenv("BATCH_SIZE", "8"))


def _ensure_index(index_name: str):
    """Create the vector index if it does not exist, or recreate if mapping is wrong."""
    if os_client.indices.exists(index=index_name):
        try:
            mapping = os_client.indices.get_mapping(index=index_name)
            props = mapping[index_name]["mappings"].get("properties", {})
            if "embedding" in props and props["embedding"].get("type") == "knn_vector":
                print(f"[INFO] Index '{index_name}' exists with correct mapping — skipping creation.")
                return
            print(f"[WARN] Index '{index_name}' has stale mapping — deleting and recreating.")
            os_client.indices.delete(index=index_name)
        except Exception as e:
            print(f"[WARN] Could not validate mapping for '{index_name}': {e} — recreating.")
            os_client.indices.delete(index=index_name)

    os_client.indices.create(
        index=index_name,
        body={
            "settings": {
                "index": {
                    "knn": True
                }
            },
            "mappings": {
                "properties": {
                    "review_id":       {"type": "keyword"},
                    "restaurant_name": {"type": "keyword"},
                    "rating":          {"type": "float"},
                    "text":            {"type": "text"},
                    "embedding":       {"type": "knn_vector", "dimension": VECTOR_DIM}
                }
            }
        }
    )
    print(f"[INFO] Created index '{index_name}' with {VECTOR_DIM}-dim embedding field")


def _embed_batch(texts):
    """Generate Titan embeddings for a list of texts (one call per text for stability)."""
    vecs = []
    for t in texts:
        resp = bedrock_rt.invoke_model(
            modelId=EMBED_MODEL,
            body=json.dumps({"inputText": t}),
            accept="application/json",
            contentType="application/json",
        )
        payload = json.loads(resp["body"].read())
        vecs.append(payload["embedding"])
    return vecs


def _bulk_upsert(index_name, docs):
    """Bulk upsert documents to OpenSearch."""
    actions = [
        {
            "_op_type": "index",
            "_index": index_name,
            "_id": d["review_id"],
            "_source": d
        }
        for d in docs
    ]
    if actions:
        success, failed = bulk(os_client, actions)
        print(f"[INFO] Bulk upsert: {success} succeeded, {failed} failed")


def _iter_csv_rows(
    s3_uri,
    text_col="review_text",
    id_col="review_id",
    location_col="location",
    rating_col="rating_1_5",
):
    """Iterator over rows from an S3 CSV file."""
    assert s3_uri.startswith("s3://"), f"Invalid S3 URI: {s3_uri}"
    bucket, key = s3_uri[5:].split("/", 1)

    s3_client = boto3.client("s3")
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
    except Exception as e:
        print(f"[ERROR] Failed to get object: {e}")
        return

    try:
        body_bytes = response["Body"].read()
        body = body_bytes.decode("utf-8", errors="replace")
    except Exception as e:
        print(f"[ERROR] Failed to read/parse S3 object body: {e}")
        return

    if len(body.strip()) == 0:
        print("[WARN] File appears empty — skipping.")
        return

    # Detect delimiter
    sample = body.splitlines()[0]
    comma_count = sample.count(",")
    semicolon_count = sample.count(";")
    tab_count = sample.count("\t")

    if semicolon_count > comma_count and semicolon_count > tab_count:
        delimiter = ";"
    elif tab_count > comma_count:
        delimiter = "\t"
    else:
        delimiter = ","

    reader = csv.DictReader(io.StringIO(body, newline=""), delimiter=delimiter)

    count = 0
    for row in reader:
        try:
            text = str(row.get(text_col, "") or "").strip()
            if not text:
                continue
            count += 1
            location = str(row.get(location_col, "") or "").strip()
            yield {
                "review_id": str(row.get(id_col, "")),
                "restaurant_name": location if location else "Unknown",
                "rating": float(row.get(rating_col) or 0.0),
                "text": text,
            }
        except Exception as e:
            print(f"[WARN] Skipping bad row #{count}: {e}")
            continue


def handler(event, context):
    """
    Event options:
      {"s3_csv_uri": "s3://bucket/processed/processed_final.csv", "os_index": "reviews"}
       or
      {"records": [ {review_id, restaurant_name, rating, text}, ... ], "os_index": "reviews"}
    """
    start_time = time.time()
    index_name = event.get("os_index", DEFAULT_IDX)
    _ensure_index(index_name)

    # Source: S3 CSV or direct records
    if "s3_csv_uri" in event:
        docs_iter = _iter_csv_rows(event["s3_csv_uri"])
    elif "records" in event:
        docs_iter = (r for r in event["records"])
    else:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Provide 's3_csv_uri' or 'records'"}),
        }

    batch = []
    ingested = 0
    for doc in docs_iter:
        batch.append(doc)
        if len(batch) >= BATCH:
            vecs = _embed_batch([d["text"] for d in batch])
            for d, v in zip(batch, vecs):
                d["embedding"] = v
            _bulk_upsert(index_name, batch)
            ingested += len(batch)

            if ingested % 500 == 0 and ingested > 0:
                elapsed = time.time() - start_time
                print(f"[PROGRESS] Embedded {ingested} records in {elapsed:.1f}s")

            batch = []

    if batch:
        vecs = _embed_batch([d["text"] for d in batch])
        for d, v in zip(batch, vecs):
            d["embedding"] = v
        _bulk_upsert(index_name, batch)
        ingested += len(batch)

    total_elapsed = time.time() - start_time
    print(f"[PROGRESS] Completed embedding. Total records: {ingested} in {total_elapsed:.1f}s")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "status": "ok",
            "index": index_name,
            "ingested": ingested
        }),
    }
