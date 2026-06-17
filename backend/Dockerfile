# ──────────────────────────────────────────────────────────────
# Ignisia26 — FastAPI backend (RAG engine + API)
# Build:  docker build -t ignisia26-backend ./backend
# ──────────────────────────────────────────────────────────────
FROM python:3.11-slim

# System libs occasionally needed by pdfplumber / pillow / torch wheels.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libgl1 \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models

WORKDIR /app

# Install dependencies first so they cache across code changes.
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# Bake the embedding model into the image so the first request is fast
# and the container needs no network access to Hugging Face at runtime.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Copy application code (engine package, routers, services, config).
COPY . .

EXPOSE 8000

# host 0.0.0.0 so the port is reachable from outside the container.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
