"""Pydantic schemas for shared SQL group API."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

LibraryScope = Literal["personal", "shared"]


class SharedGroupStatusResponse(BaseModel):
    group_id: int
    group_name: str
    owner_email: str
    is_owner: bool
    status: str | None = None
    role: str | None = None
    can_access: bool


class SharedGroupMemberItem(BaseModel):
    id: int
    email: str
    role: str
    status: str
    created_at: datetime | None = None
    approved_at: datetime | None = None


class SharedGroupMemberListResponse(BaseModel):
    items: list[SharedGroupMemberItem]


class SharedSqlListItem(BaseModel):
    id: int
    file_name: str
    business: str | None = None
    scene: str | None = None
    metrics: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    dimensions: list[str] = Field(default_factory=list)
    core_tables: list[str] = Field(default_factory=list)
    authors: list[str] = Field(default_factory=list)
    description: str | None = None
    storage_mode: str = "public"
    is_public: bool = True
    uploaded_by: str = ""
    index_status: str | None = None
    scope: str = "shared"


class SharedSqlListResponse(BaseModel):
    total: int
    list: list[SharedSqlListItem]


class SharedSqlDetail(SharedSqlListItem):
    sql_content: str | None = None
    comment_block: str | None = None
    created_at: str | None = None


class SharedSqlCreateRequest(BaseModel):
    full_content: str = Field(..., min_length=1)
    file_name: str | None = None
    storage_mode: Literal["public", "encrypted"] = "public"
    is_public: bool = True


class SharedSqlBatchItem(BaseModel):
    file_name: str | None = None
    full_content: str
    storage_mode: Literal["public", "encrypted"] = "public"
    is_public: bool = True


class SharedSqlBatchSaveRequest(BaseModel):
    items: list[SharedSqlBatchItem]


class SharedSqlBatchSaveResponse(BaseModel):
    success: bool
    inserted: int
    updated: int
    errors: list[str] = Field(default_factory=list)


class MemberActionRequest(BaseModel):
    email: str = Field(..., min_length=3)
