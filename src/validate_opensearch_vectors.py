import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth
import json

# === Configuration ===
region = "eu-central-1"
service = "aoss"
host = "vpc-tastetrend-rag-xxxxxx.eu-central-1.aoss.amazonaws.com"  # replace with your collection endpoint
index_name = "reviews_v1"

# === Create AWS Auth ===
credentials = boto3.Session().get_credentials()
auth = AWSV4SignerAuth(credentials, region, service)

# === Initialize OpenSearch Client ===
client = OpenSearch(
    hosts=[{"host": host, "port": 443}],
    http_auth=auth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)

# === Basic Validation Queries ===

# 1. Check if index exists
print("\n=== Checking index ===")
if client.indices.exists(index=index_name):
    print(f"✅ Index '{index_name}' exists.")
else:
    print(f"❌ Index '{index_name}' not found. Check ingestion or endpoint.")
    exit(1)

# 2. Count total documents
print("\n=== Counting documents ===")
count = client.count(index=index_name)["count"]
print(f"Total documents indexed: {count}")

# 3. Fetch a random document
print("\n=== Sample document ===")
resp = client.search(
    index=index_name,
    body={
        "query": {"match_all": {}},
        "size": 1
    }
)
print(json.dumps(resp["hits"]["hits"][0]["_source"], indent=2))
