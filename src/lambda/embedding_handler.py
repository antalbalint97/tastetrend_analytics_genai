"""
TasteTrend Analytics — Embedding Lambda (batch)
- Reads processed reviews
- Generates Titan embeddings on Bedrock
- Upserts vectors into OpenSearch (provisioned domain)
"""

import os
import io
import json
import math
import boto3
import pyarrow.parquet as pq
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth

# --- Env ---
AWS_REGION  = os.getenv("AWS_REGION", "eu-central-1")
OS_ENDPOINT = os.environ["OS_ENDPOINT"]                 # e.g. vpc-xxx.eu-central-1.es.amazonaws.com
DEFAULT_IDX = os.getenv("OS_INDEX", "reviews_v1")

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
)

EMBED_MODEL = "amazon.titan-embed-text-v2:0"
VECTOR_DIM = int(os.getenv("VECTOR_DIM", "1536"))
BATCH       = int(os.getenv("BATCH_SIZE", "8"))

def _ensure_index(index_name: str):
    if not os_client.indices.exists(index_name):
        os_client.indices.create(
            index_name,
            body={
                "settings": {"index": {"knn": True}},
                "mappings": {
                    "properties": {
                        "review_id": {"type": "keyword"},
                        "location":  {"type": "keyword"},
                        "rating":    {"type": "float"},
                        "text":      {"type": "text"},
                        "vector":    {"type": "knn_vector", "dimension": VECTOR_DIM}
                    }
                }
            }
        )

def _embed_batch(texts):
    # Titan v2 supports single input; we call per text for stability and bounded payload size
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
    bulk = []
    for d in docs:
        bulk.append({"index": {"_index": index_name, "_id": d["review_id"]}})
        bulk.append(d)
    if bulk:
        os_client.bulk(body="\n".join(map(json.dumps, bulk)) + "\n")

def _iter_parquet_rows(s3_uri, text_col="text", id_col="review_id", location_col="location", rating_col="rating"):
    assert s3_uri.startswith("s3://")
    bucket, key = s3_uri[5:].split("/", 1)
    obj = s3.get_object(Bucket=bucket, Key=key)
    table = pq.read_table(io.BytesIO(obj["Body"].read()))
    df = table.to_pandas()  # dataset is small in PoC; if it grows, switch to Arrow scanning

    for _, r in df.iterrows():
        text = str(r[text_col]) if r[text_col] is not None else ""
        if not text.strip():
            continue
        yield {
            "review_id": str(r[id_col]),
            "location":  str(r[location_col]) if location_col in df.columns else "NA",
            "rating":    float(r[rating_col]) if rating_col in df.columns and not math.isnan(r[rating_col]) else None,
            "text":      text
        }

def handler(event, context):
    """
    Event options:
      {"s3_parquet_uri": "s3://bucket/processed/processed_final.parquet", "os_index": "reviews_v1"}
       or
      {"records": [ {review_id, location, rating, text}, ... ], "os_index": "reviews_v1"}
    """
    index_name = event.get("os_index", DEFAULT_IDX)
    _ensure_index(index_name)

    # Source: S3 parquet
    if "s3_parquet_uri" in event:
        docs_iter = _iter_parquet_rows(event["s3_parquet_uri"])
    # Source: direct records
    elif "records" in event:
        docs_iter = (r for r in event["records"])
    else:
        return {"statusCode": 400, "body": json.dumps({"error": "Provide 's3_parquet_uri' or 'records'"})}

    # Process in batches
    batch = []
    ingested = 0
    for doc in docs_iter:
        batch.append(doc)
        if len(batch) >= BATCH:
            vecs = _embed_batch([d["text"] for d in batch])
            for d, v in zip(batch, vecs):
                d["vector"] = v
            _bulk_upsert(index_name, batch)
            ingested += len(batch)
            batch = []

    if batch:
        vecs = _embed_batch([d["text"] for d in batch])
        for d, v in zip(batch, vecs):
            d["vector"] = v
        _bulk_upsert(index_name, batch)
        ingested += len(batch)

    return {"statusCode": 200, "body": json.dumps({"status": "ok", "index": index_name, "ingested": ingested})}
