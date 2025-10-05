import os, json, math, time
import boto3
import pandas as pd
from tqdm import tqdm
from opensearchpy import OpenSearch, RequestsHttpConnection, helpers
from opensearchpy.aws4auth import AWSV4SignerAuth
from chunker import chunk_text

REGION = os.environ["AWS_REGION"]
OS_ENDPOINT = os.environ["OS_DOMAIN_ENDPOINT"]
OS_INDEX = os.environ.get("OS_INDEX", "reviews_v1")
BEDROCK_EMBED_MODEL = os.environ.get("BEDROCK_EMBED_MODEL", "amazon.titan-embed-text-v2:0")

S3_URI = os.environ.get("PROCESSED_S3_URI", "s3://YOUR_PROCESSED_BUCKET/processed_final.parquet")
TEXT_COL = os.environ.get("TEXT_COL", "text")

session = boto3.Session(region_name=REGION)
credentials = session.get_credentials()
awsauth = AWSV4SignerAuth(credentials, REGION, "es")

es = OpenSearch(
    hosts=[{"host": OS_ENDPOINT.replace("https://",""), "port": 443}],
    http_auth=awsauth, use_ssl=True, verify_certs=True,
    connection_class=RequestsHttpConnection,
)

bedrock = session.client("bedrock-runtime", region_name=REGION)

def embed_batch(texts):
    # Titan v2 supports batching via inputText array in some SDKs; if not, loop.
    # For simplicity and compatibility, call per text here; optimize later if needed.
    vecs = []
    for t in texts:
        body = {"inputText": t, "dimensions": 1024, "normalize": True}
        resp = bedrock.invoke_model(modelId=BEDROCK_EMBED_MODEL, body=json.dumps(body))
        out = json.loads(resp["body"].read())
        vecs.append(out["embedding"])
    return vecs

def make_actions(df_iter, batch_chunks=64):
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
        # group chunks into batches for embedding
        for i in range(0, len(chunks), batch_chunks):
            batch = chunks[i:i+batch_chunks]
            vectors = embed_batch(batch)
            for ch, vec in zip(batch, vectors):
                doc = {
                    "vector": vec,
                    "chunk_text": ch,
                    **meta
                }
                yield {
                    "_op_type": "index",
                    "_index": OS_INDEX,
                    "_source": doc
                }

def main():
    print("Reading Parquet from", S3_URI)
    df = pd.read_parquet(S3_URI)
    # Optional safety: drop empties
    df = df[df[TEXT_COL].notna() & (df[TEXT_COL].str.len() > 0)]

    actions = make_actions(df.iterrows(), batch_chunks=32)
    # Use streaming bulk to control memory; chunk_size tunes ES bulk payload
    success, failed = helpers.bulk(es, actions, chunk_size=500, max_retries=3, request_timeout=120, stats_only=True)
    print("Indexed:", success, "Failed:", failed)

if __name__ == "__main__":
    main()
