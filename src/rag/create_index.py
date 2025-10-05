import boto3, os
from opensearchpy import OpenSearch, RequestsHttpConnection
from opensearchpy.aws4auth import AWSV4SignerAuth

REGION = os.environ["AWS_REGION"]
OS_ENDPOINT = os.environ["OS_DOMAIN_ENDPOINT"]  # https://...
OS_INDEX = os.environ.get("OS_INDEX", "reviews_v1")

session = boto3.Session()
credentials = session.get_credentials()
awsauth = AWSV4SignerAuth(credentials, REGION, "es")

client = OpenSearch(
    hosts=[{"host": OS_ENDPOINT.replace("https://",""), "port": 443}],
    http_auth=awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)

def main():
    if client.indices.exists(OS_INDEX):
        print(f"Index {OS_INDEX} already exists")
        return

    body = {
        "settings": {
            "index": {
                "knn": True,
                "knn.algo_param.ef_search": 128
            }
        },
        "mappings": {
            "properties": {
                "vector": {
                    "type": "knn_vector",
                    "dimension": 1024,
                    "method": {
                        "name": "hnsw",
                        "space_type": "cosinesimil",
                        "engine": "nmslib",
                        "parameters": {"m": 16, "ef_construction": 128}
                    }
                },
                "chunk_text": {"type": "text"},
                "location":   {"type": "keyword"},
                "menu_item":  {"type": "keyword"},
                "rating":     {"type": "float"},
                "sentiment":  {"type": "keyword"},
                "review_id":  {"type": "keyword"},
                "ts":         {"type": "date"}
            }
        }
    }
    client.indices.create(index=OS_INDEX, body=body)
    print(f"Created index {OS_INDEX}")

if __name__ == "__main__":
    main()
