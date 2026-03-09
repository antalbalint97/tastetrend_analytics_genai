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

API_KEY_HASH = os.environ["API_KEY_HASH"]


def _extract_agent_id(raw: str) -> str:
    """Extract plain agent ID from a raw value that may be an ARN or plain ID.

    Supported formats:
      - plain ID:  "IVEGCZX9LV"
      - agent ARN: "arn:aws:bedrock:REGION:ACCOUNT:agent/IVEGCZX9LV"
    """
    if raw.startswith("arn:"):
        parts = raw.split("/")
        if len(parts) >= 2 and ":agent/" in raw:
            return parts[-1]
        raise ValueError(f"[INIT] Unexpected agent ARN format: {raw}")
    return raw.strip()


def _extract_alias_id(raw: str) -> str:
    """Extract plain alias ID from a raw value that may be an ARN or plain ID.

    Supported formats:
      - plain ID:   "NMBODVUPUR"
      - alias ARN:  "arn:aws:bedrock:REGION:ACCOUNT:agent-alias/AGENT_ID/ALIAS_ID"
    """
    if raw.startswith("arn:"):
        parts = raw.split("/")
        if len(parts) >= 3 and ":agent-alias/" in raw:
            return parts[-1]
        if len(parts) >= 2 and ":agent/" in raw:
            return parts[-1]
        raise ValueError(f"[INIT] Unexpected alias ARN format: {raw}")
    return raw.strip()


AGENT_ID = _extract_agent_id(os.environ["AGENT_ID"])
AGENT_ALIAS = _extract_alias_id(os.environ["AGENT_ALIAS"])
REGION = os.environ.get("BEDROCK_REGION", os.environ["AWS_REGION"])

print(f"[INIT] Agent config — agentId={AGENT_ID}, agentAliasId={AGENT_ALIAS}, region={REGION}")

# --- Initialize Bedrock Runtime client ---
try:
    brt = boto3.client("bedrock-agent-runtime", region_name=REGION)
    print(f"[INIT] Bedrock runtime client initialized in region: {REGION}")
except Exception as e:
    print("[ERROR] Failed to initialize Bedrock client:", str(e))
    raise


def _hash(s: str) -> str:
    """Hash a string using SHA256 (used for API key verification)."""
    return hashlib.sha256(s.encode()).hexdigest()


def _json_response(status_code, body):
    """Build a standard API Gateway v2 JSON response."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False)
    }


def handler(event, context):
    """
    Lambda entrypoint — proxy between API Gateway and Bedrock Agent.
    Returns a stable frontend-friendly JSON contract.
    """
    start_time = time.time()

    # --- Authorization ---
    headers = event.get("headers") or {}
    api_key = headers.get("x-api-key") or headers.get("X-API-Key")
    if not api_key:
        return _json_response(401, {"error": "Unauthorized: missing API key"})

    if _hash(api_key) != API_KEY_HASH:
        return _json_response(401, {"error": "Unauthorized: invalid key"})

    # --- Parse request body ---
    try:
        body = json.loads(event.get("body") or "{}")
    except Exception:
        return _json_response(400, {"error": "Invalid JSON body"})

    user_query = (body.get("query") or "").strip()
    if not user_query:
        return _json_response(400, {"error": "Missing 'query'"})

    conv_id = body.get("conversation_id") or context.aws_request_id
    print(f"[INFO] Invoking Agent {AGENT_ID}:{AGENT_ALIAS} | Session: {conv_id} | Query: '{user_query}'")

    # --- Invoke Bedrock Agent ---
    try:
        response = brt.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS,
            sessionId=conv_id,
            inputText=user_query,
            enableTrace=True,
        )

        output_text = ""
        results = []
        stream = response.get("completion")

        if hasattr(stream, "__iter__"):
            for evt in stream:
                # Handle chunk events (streaming text)
                chunk = evt.get("chunk")
                if chunk:
                    text_bytes = chunk.get("bytes")
                    if text_bytes:
                        decoded = text_bytes.decode("utf-8", errors="ignore")
                        output_text += decoded

                # Debug logging for trace events
                if "trace" in evt:
                    event_keys = list(evt.keys())
                    print(f"[TRACE] Event keys: {event_keys}")
                    print(f"[TRACE] Full trace: {json.dumps(evt.get('trace', {}), default=str)[:500]}")

                # Handle trace events to extract tool results
                # Use `or {}` to guard against keys that exist with None values
                trace_data = (evt.get("trace") or {}).get("trace") or {}
                orchestration = trace_data.get("orchestrationTrace") or {}
                observation = orchestration.get("observation") or {}
                action_group_output = observation.get("actionGroupInvocationOutput") or {}
                if action_group_output:
                    tool_text = action_group_output.get("text", "")
                    if tool_text:
                        print(f"[TRACE] actionGroupInvocationOutput text: {tool_text[:300]}")
                        try:
                            tool_data = json.loads(tool_text)
                            # Direct format: {"results": [...]}
                            if isinstance(tool_data.get("results"), list):
                                results = tool_data["results"]
                            # Bedrock action group response wrapper format
                            elif "response" in tool_data:
                                resp_body = (tool_data.get("response") or {}).get("responseBody") or {}
                                body_str = (resp_body.get("application/json") or {}).get("body", "")
                                if body_str:
                                    inner = json.loads(body_str)
                                    if isinstance(inner.get("results"), list):
                                        results = inner["results"]
                        except (json.JSONDecodeError, TypeError) as e:
                            print(f"[WARN] Failed to parse tool output ({e}): {tool_text[:200]}")
        else:
            output_text = str(response)

    except Exception as e:
        print("[ERROR] Bedrock invocation failed:", str(e))
        traceback.print_exc()
        return _json_response(500, {"error": f"Bedrock Agent error: {str(e)}"})

    # --- Build frontend-friendly response ---
    latency_ms = round((time.time() - start_time) * 1000, 2)

    result = {
        "answer": output_text.strip(),
        "results": results,
        "conversation_id": conv_id,
        "latency_ms": latency_ms,
    }

    print(f"[INFO] Response ready | latency={latency_ms}ms | results={len(results)}")
    return _json_response(200, result)
