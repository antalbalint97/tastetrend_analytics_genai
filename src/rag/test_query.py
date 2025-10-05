import os, json
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from opensearchpy.aws4auth import AWSV4SignerAuth

REGION = os.environ["AWS_REGION"]
OS_ENDPOINT = os.environ["OS_DOMAIN_ENDPOINT"]
OS_INDEX = os.environ.get("OS_INDEX", "reviews_v1")
BEDROCK_EMBED_MODEL = os.environ.get("BEDROCK_EMBED_MODEL", "amazon.titan-embed-text-v2:0")

session = boto3.Session(region_name=REGION)
credentials = session.get_credentials()
awsauth = AWSV4SignerAuth(credentials, REGION, "es")
es = OpenSearch(
    hosts=[{"host": OS_ENDPOINT.replace("https://",""), "port": 443}],
    http_auth=awsauth, use_ssl=True, verify_certs=True,
    connection_class=RequestsHttpConnection,
)
bedrock = session.client("bedrock-runtime", region_name=REGION)

def embed(q: str):
    body = {"inputText": q, "dimensions": 1024, "normalize": True}
    resp = bedrock.invoke_model(modelId=BEDROCK_EMBED_MODEL, body=json.dumps(body))
    return json.loads(resp["body"].read())["embedding"]

def search(q: str, k=6, filters=None, ef_search=128):
    vec = embed(q)
    query = {
        "size": k,
        "query": {
            "knn": {
                "vector": {
                    "vector": vec,
                    "k": k
                }
            }
        }
    }
    # metadata filters
    if filters:
        filter_clauses = []
        for field, value in filters.items():
            if isinstance(value, list):
                filter_clauses.append({"terms": {field: value}})
            else:
                filter_clauses.append({"term": {field: value}})
        query = {
            "size": k,
            "query": {
                "bool": {
                    "filter": filter_clauses,
                    "must": [query["query"]]
                }
            }
        }
    params = {"search_pipeline": "", "knn.algo_param.ef_search": ef_search}
    res = es.search(index=OS_INDEX, body=query, params=params)
    hits = res["hits"]["hits"]
    return [{"score": h["_score"], **h["_source"]} for h in hits]

if __name__ == "__main__":
    results = search("What do customers like most about the Uptown location?", k=6, filters={"location":"Uptown"})
    for r in results:
        print(f"{r['score']:.3f} | {r.get('location')} | {r['chunk_text'][:140]}...")
