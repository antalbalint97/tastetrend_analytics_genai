# import os, json, boto3, hashlib, base64, time

# AGENT_ID     = os.environ["AGENT_ID"]
# AGENT_ALIAS  = os.environ["AGENT_ALIAS"]
# REGION       = os.environ["AWS_REGION"]
# API_KEY_HASH = os.environ["API_KEY_HASH"]

# required_envs = ["AGENT_ID", "AGENT_ALIAS", "AWS_REGION", "API_KEY_HASH"]
# for env in required_envs:
#     if env not in os.environ or not os.environ[env]:
#         raise ValueError(f"Missing required environment variable: {env}")

# brt = boto3.client("bedrock-agent-runtime", region_name=REGION)
# print("[DEBUG] Bedrock runtime endpoint:", brt.meta.endpoint_url)


# def _hash(s: str):
#     return hashlib.sha256(s.encode()).hexdigest()


# def handler(event, context):
#     # --- Authorization ---
#     headers = event.get("headers") or {}
#     api_key = headers.get("x-api-key") or headers.get("X-API-Key")
#     if not api_key or _hash(api_key) != API_KEY_HASH:
#         return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized"})}

#     # --- Parse request ---
#     try:
#         body = json.loads(event.get("body") or "{}")
#     except Exception:
#         return {"statusCode": 400, "body": json.dumps({"error": "invalid JSON body"})}

#     user_query = (body.get("query") or "").strip()
#     if not user_query:
#         return {"statusCode": 400, "body": json.dumps({"error": "missing 'query'"})}

#     conv_id = body.get("conversation_id") or context.aws_request_id
#     print(f"[DEBUG] Invoking agent {AGENT_ID}:{AGENT_ALIAS} | Query: {user_query}")

#     # --- Invoke the Bedrock Agent ---
#     try:
#         response = brt.invoke_agent(
#             agentId=AGENT_ID,
#             agentAliasId=AGENT_ALIAS,
#             sessionId=conv_id,
#             inputText=user_query,
#         )

#         # --- Process streaming response ---
#         output_text = ""
#         refs = []
#         stream = response.get("completion")

#         if hasattr(stream, "__iter__"):
#             print("[DEBUG] Streaming Bedrock events...")
#             for event in stream:
#                 event_type = event.get("type")
#                 if not event_type:
#                     continue

#                 print(f"[DEBUG] Event type: {event_type}")

#                 # Handle normal response tokens
#                 if event_type == "responseStream":
#                     content = event.get("responseStream", {})

#                     # Handle token-by-token stream (bytes)
#                     if "chunk" in content:
#                         chunk = content["chunk"]
#                         text_bytes = chunk.get("bytes")
#                         if text_bytes:
#                             decoded = text_bytes.decode("utf-8", errors="ignore")
#                             output_text += decoded
#                             print(f"[STREAM] {decoded.strip()}")

#                     # Handle structured output text
#                     elif "outputText" in content:
#                         text = content["outputText"]
#                         output_text += text
#                         print(f"[STREAM] {text.strip()}")

#                 # Handle final response event
#                 elif event_type == "finalResponse":
#                     final = event.get("finalResponse", {})
#                     if isinstance(final, dict):
#                         output_text += final.get("outputText", "")
#                         refs = final.get("knowledgeBaseRetrievalResults", [])
#                     print(f"[DEBUG] FinalResponse received.")

#                 # Handle errors if present
#                 elif event_type == "error":
#                     print(f"[ERROR] Bedrock stream error: {event}")

#         else:
#             print("[WARN] Non-streaming response received; dumping raw object")
#             print(json.dumps(response, default=str))
#             output_text = str(response)

#     except Exception as e:
#         print("[ERROR] Bedrock invocation failed:", str(e))
#         return {"statusCode": 500, "body": json.dumps({"error": str(e)})}

#     # --- Construct and log final result ---
#     result = {
#         "answer": output_text.strip(),
#         "references": refs,
#         "conversation_id": conv_id,
#     }

#     print("[DEBUG] Final response to API Gateway:", json.dumps(result, ensure_ascii=False))
#     return {"statusCode": 200, "body": json.dumps(result)}

import os, json, boto3, hashlib, base64, time

AGENT_ID     = os.environ["AGENT_ID"]
AGENT_ALIAS  = os.environ["AGENT_ALIAS"]
REGION       = os.environ["AWS_REGION"]
API_KEY_HASH = os.environ["API_KEY_HASH"]

required_envs = ["AGENT_ID", "AGENT_ALIAS", "AWS_REGION", "API_KEY_HASH"]
for env in required_envs:
    if env not in os.environ or not os.environ[env]:
        raise ValueError(f"Missing required environment variable: {env}")

brt = boto3.client("bedrock-agent-runtime", region_name=REGION)
print("[DEBUG] Bedrock runtime endpoint:", brt.meta.endpoint_url)


def _hash(s: str):
    return hashlib.sha256(s.encode()).hexdigest()


def handler(event, context):
    # --- Handle Bedrock system validation (alias creation, warmup, etc.) ---
    if isinstance(event, dict) and "actionGroup" in event:
        print("[DEBUG] Detected Bedrock validation call:", event)
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Validation OK"})
        }

    # --- Authorization (for API Gateway calls) ---
    headers = event.get("headers") or {}
    api_key = headers.get("x-api-key") or headers.get("X-API-Key")
    if not api_key or _hash(api_key) != API_KEY_HASH:
        return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized"})}

    # --- Parse request ---
    try:
        body = json.loads(event.get("body") or "{}")
    except Exception:
        return {"statusCode": 400, "body": json.dumps({"error": "invalid JSON body"})}

    user_query = (body.get("query") or "").strip()
    if not user_query:
        return {"statusCode": 400, "body": json.dumps({"error": "missing 'query'"})}

    conv_id = body.get("conversation_id") or context.aws_request_id
    print(f"[DEBUG] Invoking agent {AGENT_ID}:{AGENT_ALIAS} | Query: {user_query}")

    # --- Invoke the Bedrock Agent ---
    try:
        response = brt.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS,
            sessionId=conv_id,
            inputText=user_query,
        )

        # --- Process streaming response ---
        output_text = ""
        refs = []
        stream = response.get("completion")

        if hasattr(stream, "__iter__"):
            print("[DEBUG] Streaming Bedrock events...")
            for event in stream:
                event_type = event.get("type")
                if not event_type:
                    continue

                print(f"[DEBUG] Event type: {event_type}")

                if event_type == "responseStream":
                    content = event.get("responseStream", {})
                    if "chunk" in content:
                        chunk = content["chunk"]
                        text_bytes = chunk.get("bytes")
                        if text_bytes:
                            decoded = text_bytes.decode("utf-8", errors="ignore")
                            output_text += decoded
                            print(f"[STREAM] {decoded.strip()}")
                    elif "outputText" in content:
                        text = content["outputText"]
                        output_text += text
                        print(f"[STREAM] {text.strip()}")

                elif event_type == "finalResponse":
                    final = event.get("finalResponse", {})
                    if isinstance(final, dict):
                        output_text += final.get("outputText", "")
                        refs = final.get("knowledgeBaseRetrievalResults", [])
                    print(f"[DEBUG] FinalResponse received.")

                elif event_type == "error":
                    print(f"[ERROR] Bedrock stream error: {event}")

        else:
            print("[WARN] Non-streaming response received; dumping raw object")
            print(json.dumps(response, default=str))
            output_text = str(response)

    except Exception as e:
        print("[ERROR] Bedrock invocation failed:", str(e))
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}

    # --- Construct final result ---
    result = {
        "answer": output_text.strip(),
        "references": refs,
        "conversation_id": conv_id,
    }

    print("[DEBUG] Final response to API Gateway:", json.dumps(result, ensure_ascii=False))
    return {"statusCode": 200, "body": json.dumps(result)}
