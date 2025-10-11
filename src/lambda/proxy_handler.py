import os, json, boto3, base64, time

AGENT_ID     = os.environ["AGENT_ID"]
AGENT_ALIAS  = os.environ["AGENT_ALIAS"]
REGION       = os.environ["AWS_REGION"]
API_KEY_HASH = os.environ["API_KEY_HASH"]  # store a SHA256 of the api key

brt = boto3.client("bedrock-agent-runtime", region_name=REGION)

def _hash(s):
    import hashlib
    return hashlib.sha256(s.encode()).hexdigest()

def handler(event, context):
    # Auth
    headers = event.get("headers") or {}
    api_key = headers.get("x-api-key") or headers.get("X-API-Key")
    if not api_key or _hash(api_key) != API_KEY_HASH:
        return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized"})}

    body = json.loads(event.get("body") or "{}")
    user_query = body.get("query","").strip()
    if not user_query:
        return {"statusCode": 400, "body": json.dumps({"error":"missing 'query'"})}

    # Optional: pass conversationId from client for stateful sessions
    conv_id = body.get("conversation_id") or context.aws_request_id

    resp = brt.invoke_agent(
        agentId=AGENT_ID,
        agentAliasId=AGENT_ALIAS,
        sessionId=conv_id,
        inputText=user_query,
    )

    # Stream or aggregate final text
    chunks = []
    # for evt in resp.get("completion",""):
    #     # in boto3 streaming, handle event stream; simplified here for non-streaming SDK returns
    #     pass
    # Bedrock Agent SDK may return streaming events in future versions
    output_text = resp.get("outputText") or resp.get("completion") or ""

    # Fallback: many SDKs now return 'outputText'
    output_text = resp.get("outputText") or ""
    refs = resp.get("knowledgeBaseRetrievalResults") or []

    return {
        "statusCode": 200,
        "body": json.dumps({
            "answer": output_text,
            "references": refs,
            "conversation_id": conv_id
        })
    }
