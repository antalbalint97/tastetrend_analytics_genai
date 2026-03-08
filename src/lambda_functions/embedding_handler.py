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
VECTOR_DIM  = int(os.getenv("VECTOR_DIM", "1024"))   # Titan v2 default output is 1024-dim
BATCH       = int(os.getenv("BATCH_SIZE", "8"))


def _ensure_index(index_name: str):
    """Create the vector index if it does not exist, or recreate if mapping is wrong."""
    if os_client.indices.exists(index=index_name):
        try:
            mapping = os_client.indices.get_mapping(index=index_name)
            props = mapping[index_name]["mappings"].get("properties", {})
            emb_props = props.get("embedding", {})
            existing_dim = emb_props.get("dimension")
            if (
                emb_props.get("type") == "knn_vector"
                and existing_dim == VECTOR_DIM
            ):
                print(f"[INFO] Index '{index_name}' exists with correct mapping "
                      f"(dimension={existing_dim}) — skipping creation.")
                return
            print(f"[WARN] Index '{index_name}' mapping mismatch "
                  f"(existing dimension={existing_dim}, required={VECTOR_DIM}) "
                  f"— deleting and recreating.")
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
        try:
            success, failed = bulk(os_client, actions, raise_on_error=True)
            print(f"[INFO] Bulk upsert: {success} succeeded, {failed} failed")
        except Exception as e:
            print(f"[ERROR] Bulk upsert failed for index '{index_name}': {e}")
            raise RuntimeError(
                f"OpenSearch bulk upsert failed for index '{index_name}': {e}"
            ) from e


def _iter_csv_rows(
    s3_uri,
    counters,
    text_col="review_text",
    id_col="review_id",
    location_col="location",
    rating_col="rating_1_5",
):
    """Iterator over rows from an S3 CSV file. Updates *counters* in place."""
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

    for row in reader:
        counters["total_rows_read"] += 1
        try:
            text = str(row.get(text_col, "") or "").strip()
            if not text:
                counters["skipped_rows"] += 1
                continue
            location = str(row.get(location_col, "") or "").strip()
            counters["valid_rows"] += 1
            yield {
                "review_id": str(row.get(id_col, "")),
                "restaurant_name": location if location else "Unknown",
                "rating": float(row.get(rating_col) or 0.0),
                "text": text,
            }
        except Exception as e:
            counters["skipped_rows"] += 1
            print(f"[WARN] Skipping bad row #{counters['total_rows_read']}: {e}")
            continue


def _iter_records(records, counters):
    """Iterator over direct record dicts. Updates *counters* in place."""
    for rec in records:
        counters["total_rows_read"] += 1
        try:
            text = str(rec.get("text", "") or "").strip()
            if not text:
                counters["skipped_rows"] += 1
                continue
            counters["valid_rows"] += 1
            yield {
                "review_id": str(rec.get("review_id", "")),
                "restaurant_name": str(rec.get("restaurant_name", "") or "Unknown"),
                "rating": float(rec.get("rating") or 0.0),
                "text": text,
            }
        except Exception as e:
            counters["skipped_rows"] += 1
            print(f"[WARN] Skipping bad record #{counters['total_rows_read']}: {e}")
            continue


def _verify_index_count(index_name, expected_count):
    """Query OpenSearch _count API and compare with expected document count."""
    try:
        resp = os_client.count(index=index_name)
        actual_count = resp.get("count", 0)
        match = actual_count == expected_count
        print(f"[INFO] Verification: index '{index_name}' has {actual_count} docs, "
              f"expected {expected_count}, match={match}")
        return {
            "expected_documents": expected_count,
            "verified_document_count": actual_count,
            "count_matches": match,
        }
    except Exception as e:
        print(f"[WARN] Verification failed for index '{index_name}' "
              f"(expected {expected_count} docs): {e}")
        return {
            "expected_documents": expected_count,
            "verified_document_count": None,
            "count_matches": False,
        }


def _process_batch(batch, index_name, counters, warnings):
    """Embed and index a batch of documents. Updates *counters* and *warnings* in place."""
    batch_size = len(batch)

    # --- Embed ---
    try:
        vecs = _embed_batch([d["text"] for d in batch])
        for d, v in zip(batch, vecs):
            d["embedding"] = v
        counters["embedded_rows"] += batch_size
    except Exception as e:
        counters["failed_rows"] += batch_size
        msg = f"Embedding failed for batch of {batch_size}: {e}"
        print(f"[ERROR] {msg}")
        warnings.append(msg)
        return

    # --- Index ---
    try:
        _bulk_upsert(index_name, batch)
        counters["indexed_rows"] += batch_size
    except Exception as e:
        counters["failed_rows"] += batch_size
        msg = f"Indexing failed for batch of {batch_size}: {e}"
        print(f"[ERROR] {msg}")
        warnings.append(msg)


def handler(event, context):
    """
    Event options:
      {"s3_csv_uri": "s3://bucket/processed/processed_final.csv", "os_index": "reviews"}
       or
      {"records": [ {review_id, restaurant_name, rating, text}, ... ], "os_index": "reviews"}
    """
    start_time = time.time()
    index_name = event.get("os_index", DEFAULT_IDX)

    counters = {
        "total_rows_read": 0,
        "valid_rows": 0,
        "skipped_rows": 0,
        "embedded_rows": 0,
        "indexed_rows": 0,
        "failed_rows": 0,
    }
    warnings = []

    try:
        _ensure_index(index_name)
    except Exception as e:
        print(f"[ERROR] Failed to ensure index '{index_name}': {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"Index setup failed: {e}"}),
        }

    # Source: S3 CSV or direct records
    if "s3_csv_uri" in event:
        docs_iter = _iter_csv_rows(event["s3_csv_uri"], counters)
    elif "records" in event:
        docs_iter = _iter_records(event["records"], counters)
    else:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Provide 's3_csv_uri' or 'records'"}),
        }

    batch = []
    for doc in docs_iter:
        batch.append(doc)
        if len(batch) >= BATCH:
            _process_batch(batch, index_name, counters, warnings)

            if counters["indexed_rows"] % 500 == 0 and counters["indexed_rows"] > 0:
                elapsed = time.time() - start_time
                print(f"[PROGRESS] Indexed {counters['indexed_rows']} records in {elapsed:.1f}s")

            batch = []

    if batch:
        _process_batch(batch, index_name, counters, warnings)

    total_elapsed = time.time() - start_time
    valid = counters["valid_rows"]
    success_rate = (counters["indexed_rows"] / valid) if valid > 0 else 0.0

    print(f"[PROGRESS] Completed embedding. "
          f"indexed={counters['indexed_rows']}/{valid} valid rows "
          f"({success_rate:.1%}) in {total_elapsed:.1f}s")

    status = "ok" if counters["failed_rows"] == 0 else "partial"
    status_code = 200 if counters["failed_rows"] == 0 else 207

    verification = _verify_index_count(index_name, valid)

    return {
        "statusCode": status_code,
        "body": json.dumps({
            "status": status,
            "index": index_name,
            "total_rows_read": counters["total_rows_read"],
            "valid_rows": counters["valid_rows"],
            "skipped_rows": counters["skipped_rows"],
            "embedded_rows": counters["embedded_rows"],
            "indexed_rows": counters["indexed_rows"],
            "failed_rows": counters["failed_rows"],
            "success_rate": round(success_rate, 4),
            "expected_documents": verification["expected_documents"],
            "verified_document_count": verification["verified_document_count"],
            "count_matches": verification["count_matches"],
            "warnings": warnings,
        }),
    }
