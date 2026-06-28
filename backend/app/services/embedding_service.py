"""OpenAI-compatible + local fallback text embeddings."""

from __future__ import annotations

import logging
import math
import threading
from typing import Protocol

import httpx

from app.config import (
    EMBEDDING_BATCH_SIZE,
    EMBEDDING_DIM,
    EMBEDDING_MODEL,
    EMBEDDING_PROVIDER,
    EMBEDDING_USE_FASTEMBED_FALLBACK,
    LLM_API_KEY,
    LLM_BASE_URL,
    LLM_TIMEOUT,
)
from app.services.llm_service import is_llm_configured

logger = logging.getLogger(__name__)

_fastembed_model = None
_fastembed_lock = threading.Lock()


class EmbeddingProvider(Protocol):
    def embed_texts(self, texts: list[str]) -> list[list[float]]: ...


def _normalize(vec: list[float]) -> list[float]:
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


def _hash_embed(text: str, dim: int = EMBEDDING_DIM) -> list[float]:
    """Deterministic lightweight fallback when API/local model unavailable."""
    vec = [0.0] * dim
    tokens = text.lower().split()
    for token in tokens:
        h = hash(token)
        idx = abs(h) % dim
        sign = 1.0 if h % 2 == 0 else -1.0
        vec[idx] += sign
    return _normalize(vec)


def _get_fastembed_model():
    global _fastembed_model
    if _fastembed_model is not None:
        return _fastembed_model
    with _fastembed_lock:
        if _fastembed_model is None:
            from fastembed import TextEmbedding

            _fastembed_model = TextEmbedding(model_name="BAAI/bge-small-zh-v1.5")
    return _fastembed_model


def _embed_with_fastembed(texts: list[str]) -> list[list[float]]:
    model = _get_fastembed_model()
    vectors = list(model.embed(texts))
    return [_normalize(list(map(float, vec))) for vec in vectors]


def _embed_with_api(texts: list[str]) -> list[list[float]]:
    url = f"{LLM_BASE_URL.rstrip('/')}/embeddings"
    headers = {
        "Authorization": f"Bearer {LLM_API_KEY}",
        "Content-Type": "application/json",
    }
    vectors: list[list[float]] = []
    with httpx.Client(timeout=LLM_TIMEOUT) as client:
        for i in range(0, len(texts), EMBEDDING_BATCH_SIZE):
            batch = texts[i : i + EMBEDDING_BATCH_SIZE]
            resp = client.post(
                url,
                headers=headers,
                json={"model": EMBEDDING_MODEL, "input": batch},
            )
            resp.raise_for_status()
            data = resp.json()["data"]
            data.sort(key=lambda item: item.get("index", 0))
            vectors.extend([item["embedding"] for item in data])
    return vectors


def preload_embedding_model() -> None:
    """Warm up local embedding model on startup (avoids first-index latency)."""
    if EMBEDDING_PROVIDER == "api":
        return
    if not EMBEDDING_USE_FASTEMBED_FALLBACK:
        return
    try:
        _get_fastembed_model()
        logger.info("FastEmbed model preloaded (BAAI/bge-small-zh-v1.5)")
    except Exception as exc:
        logger.warning("FastEmbed preload failed: %s", exc)


def embed_texts(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []

    cleaned = [t.strip() or " " for t in texts]

    if EMBEDDING_PROVIDER == "api" and is_llm_configured():
        try:
            return _embed_with_api(cleaned)
        except Exception as exc:
            logger.warning("Embedding API failed: %s", exc)
            if not EMBEDDING_USE_FASTEMBED_FALLBACK:
                raise

    if EMBEDDING_PROVIDER in ("fastembed", "api") and EMBEDDING_USE_FASTEMBED_FALLBACK:
        try:
            return _embed_with_fastembed(cleaned)
        except Exception as exc:
            logger.warning("FastEmbed failed: %s", exc)

    logger.warning("Using hash embedding fallback for %s texts", len(cleaned))
    return [_hash_embed(t) for t in cleaned]
