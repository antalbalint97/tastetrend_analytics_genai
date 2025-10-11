import os, time, json, uuid, requests

API_URL = os.environ["TT_API_URL"]      # from Terraform output
API_KEY = os.environ["TT_API_KEY"]

def ask(query, conversation_id=None, timeout=15):
    st = time.time()
    resp = requests.post(
        f"{API_URL}/query",
        headers={"x-api-key": API_KEY},
        json={"query": query, "conversation_id": conversation_id or str(uuid.uuid4())},
        timeout=timeout
    )
    dt = (time.time()-st)*1000.0
    resp.raise_for_status()
    data = resp.json()
    return data["answer"], data.get("references", []), dt

def smoke_test():
    tests = [
        "What is the best restaurant overall?",
        "What is the general consensus of the downtown restaurant?",
        "What do customers like most about the Uptown location?",
        "What do people complain about in the Riverside restaurant?",
        "How does service quality compare between Uptown and Riverside?",
        "Which menu items get the best reviews?",
        "Which location has the most complaints about waiting times?",
        "What are the top 3 complaints about the Lakeside location?",
        "Do customers think our food is worth the price?",
        "What do customers say about staff friendliness across all locations?",
        "Are there recurring complaints about food temperature?",
        "Which location would you recommend to a new customer and why?",
    ]

    results = []
    for q in tests:
        ans, refs, ms = ask(q)
        results.append({"q": q, "ms": ms, "answer": ans, "refs": refs})
        print(f"{ms:.0f} ms | {q}\n -> {ans[:140]}...\n")
    return results

if __name__ == "__main__":
    smoke_test()
