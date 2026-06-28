"""Pydantic schemas for Agent API."""

from typing import Any, Literal

from pydantic import BaseModel, Field

AgentMode = Literal[
    "find_sql",
    "explain_sql",
    "recommend_similar_sql",
    "rewrite_sql",
    "cross_sql_rewrite",
    "generate_sql",
    "chat",
]


class AgentChatRequest(BaseModel):
    message: str = Field(..., min_length=1, description="User message")
    current_sql_id: int | None = Field(None, description="Currently selected SQL id")
    mode: AgentMode | None = Field(None, description="Optional mode override")


class AgentExplainRequest(BaseModel):
    sql_id: int


class AgentRecommendRequest(BaseModel):
    sql_id: int


class AgentRewriteRequest(BaseModel):
    sql_id: int
    instruction: str = Field(..., min_length=1)
    cross_sql: bool = Field(
        False,
        description="Force cross-SQL rewrite (borrow JOIN paths from library)",
    )


class AgentCrossSqlRewriteRequest(BaseModel):
    sql_id: int
    instruction: str = Field(..., min_length=1)


class AgentGenerateSqlRequest(BaseModel):
    instruction: str = Field(..., min_length=1)


class AgentChatResponse(BaseModel):
    success: bool
    mode: AgentMode | None = None
    data: dict[str, Any] | None = None
    message: str | None = None
