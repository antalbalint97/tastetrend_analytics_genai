"""
TasteTrend Analytics — Automated Evaluation Script
Evaluates RAG/Agent accuracy, latency, and semantic similarity vs GOLD references.
"""

import os, time, json, uuid, boto3, numpy as np
from .query_client import ask

# ---------- Config ----------
AWS_REGION = os.getenv("AWS_REGION", "eu-central-1")
BEDROCK_MODEL = "amazon.titan-embed-text-v2:0"

# ---------- Clients ----------
session = boto3.Session(region_name=AWS_REGION)
bedrock_rt = session.client("bedrock-runtime", region_name=AWS_REGION)

# ---------- GOLD Reference ----------
GOLD = {
    "What is the best restaurant overall?": [
        "Uptown", "high ratings", "consistent", "popular", "best overall", "top rated"
    ],
    "What is the general consensus of the downtown restaurant?": [
        "Downtown", "mixed", "service", "slow", "average", "crowded", "good food"
    ],
    "What do customers like most about the Uptown location?": [
        "Uptown", "friendly staff", "atmosphere", "ambience", "burger", "service", "vibe"
    ],
    "What do people complain about in the Riverside restaurant?": [
        "Riverside", "waiting time", "slow service", "cold food", "noise", "complaints"
    ],
    "How does service quality compare between Uptown and Riverside?": [
        "Uptown", "Riverside", "better service", "faster", "friendlier", "comparison", "difference"
    ],
    "Which menu items get the best reviews?": [
        "burger", "steak", "salad", "pasta", "pizza", "popular", "favorite"
    ],
    "Which location has the most complaints about waiting times?": [
        "Riverside", "Downtown", "waiting", "delay", "slow service", "complaints"
    ],
    "What are the top 3 complaints about the Lakeside location?": [
        "Lakeside", "waiting", "cold food", "overpriced", "slow service", "complaints"
    ],
    "Do customers think our food is worth the price?": [
        "value", "price", "worth", "expensive", "reasonable", "overpriced"
    ],
    "What do customers say about staff friendliness across all locations?": [
        "friendly", "staff", "service", "welcoming", "attentive", "helpful"
    ],
    "Are there recurring complaints about food temperature?": [
        "cold", "temperature", "undercooked", "overcooked", "complaint", "food"
    ],
    "Which location would you recommend to a new customer and why?": [
        "Uptown", "Midtown", "best", "consistent", "friendly", "recommend", "experience"
    ],
}


# ---------- Metrics ----------
def keyword_accuracy(q, ans):
    kws = GOLD.get(q, [])
    return sum(1 for k in kws if k.lower() in ans.lower()) / max(1, len(kws))


def get_embedding(text):
    """Call Titan embedding model for text -> vector"""
    resp = bedrock_rt.invoke_model(
        modelId=BEDROCK_MODEL,
        body=json.dumps({"inputText": text}),
        accept="application/json",
        contentType="application/json",
    )
    payload = json.loads(resp["body"].read())
    return np.array(payload["embedding"], dtype=np.float32)


def semantic_similarity(a, b):
    """Cosine similarity between two embedding vectors"""
    if np.linalg.norm(a) == 0 or np.linalg.norm(b) == 0:
        return 0.0
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))


def semantic_accuracy(q, ans):
    """Compare the expected keywords to the model answer semantically"""
    gold_text = " ".join(GOLD[q])
    gold_emb = get_embedding(gold_text)
    ans_emb = get_embedding(ans)
    return semantic_similarity(gold_emb, ans_emb)


def run_eval(questions):
    latencies = []
    acc_kw = []
    acc_sem = []

    for q in questions:
        print(f"[TEST] {q}")
        ans, refs, ms = ask(q)
        latencies.append(ms)
        kw_score = keyword_accuracy(q, ans)
        sem_score = semantic_accuracy(q, ans)
        acc_kw.append(kw_score)
        acc_sem.append(sem_score)
        print(f" -> KeywordAcc={kw_score:.2f}, SemanticAcc={sem_score:.2f}, {ms:.0f}ms\n")

    p95 = sorted(latencies)[int(len(latencies) * 0.95) - 1]
    return {
        "n": len(questions),
        "p95_ms": round(p95, 1),
        "avg_keyword_acc": round(sum(acc_kw) / len(acc_kw), 3),
        "avg_semantic_acc": round(sum(acc_sem) / len(acc_sem), 3),
    }


if __name__ == "__main__":
    qs = list(GOLD.keys())
    print(json.dumps(run_eval(qs), indent=2))
