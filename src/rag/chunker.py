def normalize_ws(s: str) -> str:
    return " ".join(s.split())

def chunk_text(text: str, target_chars: int = 1200, overlap: int = 240):
    t = normalize_ws(text or "")
    if not t:
        return []
    chunks = []
    start = 0
    n = len(t)
    while start < n:
        end = min(start + target_chars, n)
        chunks.append(t[start:end])
        if end == n:
            break
        start = max(0, end - overlap)
    return chunks
