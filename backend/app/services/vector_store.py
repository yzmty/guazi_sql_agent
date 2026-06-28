"""Vector store — SQLite-backed (no extra native deps, works on Python 3.13+)."""

from __future__ import annotations

import json
import logging
import math
from typing import Any, Protocol

from sqlalchemy import Column, Float, Integer, MetaData, String, Table, Text, delete, func, select
from sqlalchemy.orm import Session

from app.database import engine

logger = logging.getLogger(__name__)

_metadata = MetaData()
vector_chunks = Table(
    "vector_chunks",
    _metadata,
    Column("id", String, primary_key=True),
    Column("user_email", String, nullable=False, index=True),
    Column("sql_file_id", Integer, nullable=False, index=True),
    Column("chunk_type", String, nullable=False),
    Column("file_name", String, nullable=False, default=""),
    Column("document", Text, nullable=False),
    Column("embedding_json", Text, nullable=False),
    Column("score_cache", Float, nullable=True),
)


def _ensure_table() -> None:
    _metadata.create_all(bind=engine, tables=[vector_chunks])


def _cosine(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


class VectorStore(Protocol):
    def upsert(
        self,
        ids: list[str],
        embeddings: list[list[float]],
        documents: list[str],
        metadatas: list[dict[str, Any]],
    ) -> None: ...

    def delete_by_sql_file(self, user_email: str, sql_file_id: int) -> None: ...

    def search(
        self,
        query_embedding: list[float],
        user_email: str,
        top_k: int = 10,
    ) -> list[dict[str, Any]]: ...


class SQLiteVectorStore:
    def __init__(self) -> None:
        _ensure_table()

    def upsert(
        self,
        ids: list[str],
        embeddings: list[list[float]],
        documents: list[str],
        metadatas: list[dict[str, Any]],
    ) -> None:
        if not ids:
            return
        with Session(engine) as session:
            for vid, emb, doc, meta in zip(ids, embeddings, documents, metadatas):
                session.execute(
                    delete(vector_chunks).where(vector_chunks.c.id == vid)
                )
                session.execute(
                    vector_chunks.insert().values(
                        id=vid,
                        user_email=meta.get("user_email", ""),
                        sql_file_id=int(meta.get("sql_file_id", 0)),
                        chunk_type=str(meta.get("chunk_type", "")),
                        file_name=str(meta.get("file_name", "")),
                        document=doc,
                        embedding_json=json.dumps(emb),
                    )
                )
            session.commit()

    def delete_by_sql_file(self, user_email: str, sql_file_id: int) -> None:
        with Session(engine) as session:
            session.execute(
                delete(vector_chunks).where(
                    vector_chunks.c.user_email == user_email,
                    vector_chunks.c.sql_file_id == sql_file_id,
                )
            )
            session.commit()

    def search(
        self,
        query_embedding: list[float],
        user_email: str,
        top_k: int = 10,
    ) -> list[dict[str, Any]]:
        with Session(engine) as session:
            rows = session.execute(
                select(vector_chunks).where(vector_chunks.c.user_email == user_email)
            ).fetchall()

        scored: list[dict[str, Any]] = []
        for row in rows:
            try:
                emb = json.loads(row.embedding_json)
            except json.JSONDecodeError:
                continue
            score = _cosine(query_embedding, emb)
            scored.append(
                {
                    "id": row.id,
                    "document": row.document,
                    "metadata": {
                        "user_email": row.user_email,
                        "sql_file_id": row.sql_file_id,
                        "chunk_type": row.chunk_type,
                        "file_name": row.file_name,
                    },
                    "score": score,
                }
            )
        scored.sort(key=lambda x: x["score"], reverse=True)
        return scored[:top_k]

    def count_for_user(self, user_email: str) -> int:
        with Session(engine) as session:
            return (
                session.execute(
                    select(func.count())
                    .select_from(vector_chunks)
                    .where(vector_chunks.c.user_email == user_email)
                ).scalar()
                or 0
            )

    def count_for_sql_file(self, user_email: str, sql_file_id: int) -> int:
        with Session(engine) as session:
            return (
                session.execute(
                    select(func.count())
                    .select_from(vector_chunks)
                    .where(
                        vector_chunks.c.user_email == user_email,
                        vector_chunks.c.sql_file_id == sql_file_id,
                    )
                ).scalar()
                or 0
            )


_store: VectorStore | None = None


def get_vector_store() -> VectorStore:
    global _store
    if _store is None:
        _store = SQLiteVectorStore()
    return _store
