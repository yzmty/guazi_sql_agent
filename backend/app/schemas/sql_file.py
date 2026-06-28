"""Pydantic schemas for SQL file API."""

import json
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


def _parse_json_list(value: str | None) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
        if isinstance(parsed, list):
            return [str(item) for item in parsed]
    except (json.JSONDecodeError, TypeError):
        pass
    return []


class SqlFileListItem(BaseModel):
    """Summary row for list/search results."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    file_name: str
    business: str | None = None
    scene: str | None = None
    tags: list[str] = Field(default_factory=list)
    metrics: list[str] = Field(default_factory=list)
    dimensions: list[str] = Field(default_factory=list)
    core_tables: list[str] = Field(default_factory=list)
    authors: list[str] = Field(default_factory=list)
    description: str | None = None
    score: float | None = None
    index_status: str | None = None

    @classmethod
    def from_orm_with_score(cls, obj: Any, score: float | None = None) -> "SqlFileListItem":
        return cls(
            id=obj.id,
            file_name=obj.file_name,
            business=obj.business,
            scene=obj.scene,
            tags=_parse_json_list(obj.tags_json),
            metrics=_parse_json_list(obj.metrics_json),
            dimensions=_parse_json_list(obj.dimensions_json),
            core_tables=_parse_json_list(obj.core_tables_json),
            authors=_parse_json_list(obj.authors_json),
            description=obj.description,
            score=score,
            index_status=getattr(obj, "index_status", None),
        )


class SqlFileDetail(BaseModel):
    """Full SQL file metadata and content."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    file_name: str
    file_path: str | None = None
    metrics: list[str] = Field(default_factory=list)
    business: str | None = None
    scene: str | None = None
    tags: list[str] = Field(default_factory=list)
    dimensions: list[str] = Field(default_factory=list)
    core_tables: list[str] = Field(default_factory=list)
    authors: list[str] = Field(default_factory=list)
    description: str | None = None
    sql_content: str | None = None
    comment_block: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    index_status: str | None = "pending"
    index_error: str | None = None
    indexed_at: datetime | None = None

    @classmethod
    def from_orm(cls, obj: Any) -> "SqlFileDetail":
        return cls(
            id=obj.id,
            file_name=obj.file_name,
            file_path=obj.file_path,
            metrics=_parse_json_list(obj.metrics_json),
            business=obj.business,
            scene=obj.scene,
            tags=_parse_json_list(obj.tags_json),
            dimensions=_parse_json_list(obj.dimensions_json),
            core_tables=_parse_json_list(obj.core_tables_json),
            authors=_parse_json_list(obj.authors_json),
            description=obj.description,
            sql_content=obj.sql_content,
            comment_block=obj.comment_block,
            created_at=obj.created_at,
            updated_at=obj.updated_at,
            index_status=getattr(obj, "index_status", "pending"),
            index_error=getattr(obj, "index_error", None),
            indexed_at=getattr(obj, "indexed_at", None),
        )


class SqlFileListResponse(BaseModel):
    total: int
    list: list[SqlFileListItem]


class SyncResponse(BaseModel):
    success: bool
    total: int
    inserted: int
    updated: int
    skipped: int
    warnings: list[str] = Field(default_factory=list)


class FilterOptionsResponse(BaseModel):
    businesses: list[str] = Field(default_factory=list)
    authors: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    core_tables: list[str] = Field(default_factory=list)


class SqlContentItem(BaseModel):
    file_name: str | None = None
    full_content: str


class ParseBatchRequest(BaseModel):
    items: list[SqlContentItem]


class ParseBatchItem(BaseModel):
    file_name: str
    valid: bool
    error: str | None = None
    parsed: dict | None = None
    full_content: str | None = None


class ParseBatchResponse(BaseModel):
    items: list[ParseBatchItem]


class BatchSaveItem(BaseModel):
    id: int | None = None
    file_name: str | None = None
    full_content: str


class BatchSaveRequest(BaseModel):
    items: list[BatchSaveItem]


class BatchSaveResponse(BaseModel):
    success: bool
    inserted: int
    updated: int
    errors: list[str] = Field(default_factory=list)


class SqlFileCreateRequest(BaseModel):
    file_name: str | None = None
    full_content: str


class SqlFileUpdateRequest(BaseModel):
    file_name: str | None = None
    full_content: str
