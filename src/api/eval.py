from .query_client import ask
import json, time

# You can create a small JSON with expected keywords per question
GOLD = {
  "What is the best restaurant overall?": ["Uptown","best overall"],
  "What is the general consensus of the downtown restaurant?": ["Downtown","consensus","mixed","positive","negative"],
  # ... fill minimal keyword sets
}

def keyword_accuracy(q, ans):
    kws = GOLD.get(q, [])
    return sum(1 for k in kws if k.lower() in ans.lower()) / max(1,len(kws))

def run_eval(questions):
    latencies = []
    accs = []
    for q in questions:
        ans, refs, ms = ask(q)
        latencies.append(ms)
        accs.append(keyword_accuracy(q, ans))
    p95 = sorted(latencies)[int(len(latencies)*0.95)-1]
    avg_acc = sum(accs)/len(accs) if accs else 0
    return {"p95_ms": p95, "avg_acc": avg_acc, "n": len(questions)}

if __name__ == "__main__":
    qs = list(GOLD.keys())
    print(run_eval(qs))
