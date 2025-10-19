import os
import json
import boto3
import hashlib
import traceback
import time

# --- Environment variables ---
REQUIRED_ENVS = ["AGENT_ID", "AGENT_ALIAS", "AWS_REGION", "API_KEY_HASH"]

for env in REQUIRED_ENVS:
    if not os.environ.get(env):
        raise ValueError(f"[INIT] Missing required environment variable: {env}")

AGENT_ID = os.environ["AGENT_ID"]
AGENT_ALIAS = os.environ["AGENT_ALIAS"]
REGION = os.environ["AWS_REGION"]
API_KEY_HASH = os.environ["API_KEY_HASH"]

# --- Initialize Bedrock Runtime client ---
try:
    brt = boto3.client("bedrock-agent-runtime", region_name=REGION)
    print(f"[INIT] Bedrock runtime client initialized in region: {REGION}")
    print(f"[DEBUG] Endpoint: {brt.meta.endpoint_url}")
except Exception as e:
    print("[ERROR] Failed to initialize Bedrock client:", str(e))
    raise


def _hash(s: str) -> str:
    """Hash a string using SHA256 (used for API key verification)."""
    return hashlib.sha256(s.encode()).hexdigest()


def _log_event(prefix: str, data):
    """Pretty print debug events with consistent prefix."""
    try:
        print(f"{prefix}: {json.dumps(data, ensure_ascii=False)[:800]}")
    except Exception:
        print(f"{prefix}: {data}")


def handler(event, context):
    """
    Lambda entrypoint.
    Handles both API Gateway calls and Bedrock validation events.
    """

    start_time = time.time()
    _log_event("[DEBUG] Incoming event", event)

    # --- Handle Bedrock validation or warmup ---
    if isinstance(event, dict) and "actionGroup" in event:
        print("[DEBUG] Detected Bedrock validation/warmup event.")
        return {"statusCode": 200, "body": json.dumps({"message": "Validation OK"})}

    # --- Authorization ---
    headers = (event.get("headers") or {})
    api_key = headers.get("x-api-key") or headers.get("X-API-Key")
    if not api_key:
        print("[WARN] Missing API key in headers.")
        return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized: missing API key"})}

    if _hash(api_key) != API_KEY_HASH:
        print("[WARN] Invalid API key provided.")
        return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized: invalid key"})}

    # --- Parse request body ---
    try:
        body = json.loads(event.get("body") or "{}")
    except Exception:
        traceback.print_exc()
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid JSON body"})}

    user_query = (body.get("query") or "").strip()
    if not user_query:
        return {"statusCode": 400, "body": json.dumps({"error": "Missing 'query'"})}

    conv_id = body.get("conversation_id") or context.aws_request_id
    print(f"[DEBUG] Invoking Agent {AGENT_ID}:{AGENT_ALIAS} | Session: {conv_id} | Query: '{user_query}'")

    # --- Invoke Bedrock Agent ---
    try:
        response = brt.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS,
            sessionId=conv_id,
            inputText=user_query,
        )

        output_text = ""
        refs = []
        stream = response.get("completion")

        if hasattr(stream, "__iter__"):
            print("[DEBUG] Streaming Bedrock response...")
            for evt in stream:
                evt_type = evt.get("type")
                if not evt_type:
                    continue

                print(f"[DEBUG] Stream event: {evt_type}")

                if evt_type == "responseStream":
                    content = evt.get("responseStream", {})
                    if "chunk" in content:
                        text_bytes = content["chunk"].get("bytes")
                        if text_bytes:
                            decoded = text_bytes.decode("utf-8", errors="ignore")
                            output_text += decoded
                            print(f"[STREAM] {decoded.strip()}")
                    elif "outputText" in content:
                        text = content["outputText"]
                        output_text += text
                        print(f"[STREAM] {text.strip()}")

                elif evt_type == "finalResponse":
                    final = evt.get("finalResponse", {})
                    if isinstance(final, dict):
                        output_text += final.get("outputText", "")
                        refs = final.get("knowledgeBaseRetrievalResults", [])
                    print("[DEBUG] FinalResponse event received.")

                elif evt_type == "error":
                    _log_event("[ERROR] Bedrock stream error", evt)

        else:
            print("[WARN] Non-streaming response; dumping raw payload")
            _log_event("[DEBUG] Raw response", response)
            output_text = str(response)

    except Exception as e:
        print("[ERROR] Bedrock invocation failed:", str(e))
        traceback.print_exc()
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}

    # --- Final response ---
    result = {
        "answer": output_text.strip(),
        "references": refs,
        "conversation_id": conv_id,
        "latency_ms": round((time.time() - start_time) * 1000, 2),
    }

    _log_event("[DEBUG] Returning result", result)
    return {"statusCode": 200, "body": json.dumps(result)}
