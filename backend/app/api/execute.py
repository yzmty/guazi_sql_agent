"""SQL execution API."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database import get_db
from app.services.auth_service import CurrentUser
from app.services.doris_service import (
    SqlExecutionError,
    apply_sql_params,
    detect_dollar_params,
    execute_query,
)
from app.services.search_service import get_sql_file_by_id

router = APIRouter(prefix="/api/sql", tags=["sql-execute"])


class DetectParamsRequest(BaseModel):
    sql: str


class DetectParamsResponse(BaseModel):
    params: list[str]


class ExecuteSqlRequest(BaseModel):
    sql: str
    start_date: str = Field(..., description="起始日期 YYYY-MM-DD")
    end_date: str = Field(..., description="结束日期 YYYY-MM-DD")
    params: dict[str, str] = Field(default_factory=dict, description="${} 占位符替换值")
    sql_file_id: int | None = None


class ExecuteSqlResponse(BaseModel):
    columns: list[str]
    rows: list[list]
    row_count: int
    truncated: bool
    executed_sql: str


@router.post("/detect-params", response_model=DetectParamsResponse)
def detect_params(body: DetectParamsRequest) -> DetectParamsResponse:
    return DetectParamsResponse(params=detect_dollar_params(body.sql))


@router.post("/execute", response_model=ExecuteSqlResponse)
def run_sql(
    body: ExecuteSqlRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ExecuteSqlResponse:
    sql = body.sql.strip()
    if body.sql_file_id:
        record = get_sql_file_by_id(db, body.sql_file_id, user_email=user.owner_email)
        if not record:
            raise HTTPException(status_code=404, detail="SQL 不存在")
        sql = record.sql_content or sql

    if not sql:
        raise HTTPException(status_code=400, detail="SQL 不能为空")

    try:
        final_sql = apply_sql_params(
            sql,
            body.start_date.strip(),
            body.end_date.strip(),
            body.params,
        )
        result = execute_query(user.doris_user, user.doris_password, final_sql)
        return ExecuteSqlResponse(
            executed_sql=final_sql,
            **result,
        )
    except SqlExecutionError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"执行失败: {exc}") from exc
