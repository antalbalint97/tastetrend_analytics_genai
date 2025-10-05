import re

def normalize_ws(s: str) -> str:
    return " ".join(s.split())

def chunk_text(text: str, target_chars: int = 1200, overlap: int = 240):
    t = normalize_ws(text or "")
    if not t:
        return []
    # Prefer chunking on sentence boundaries if possible
    sentences = re.split(r'(?<=[.!?]) +', t)
    chunks, cur = [], ""
    for sent in sentences:
        if len(cur) + len(sent) + 1 < target_chars:
            cur += (" " + sent)
        else:
            chunks.append(cur.strip())
            cur = sent
    if cur:
        chunks.append(cur.strip())

    # Add overlap between chunks
    if overlap > 0 and len(chunks) > 1:
        overlapped = []
        for i, ch in enumerate(chunks):
            start = max(0, i - 1)
            context = " ".join(chunks[start:i+1])[-(target_chars + overlap):]
            overlapped.append(context)
        chunks = overlapped

    return chunks
