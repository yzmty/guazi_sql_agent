"""SQL files REST API routes."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database import get_db
from app.schemas.sql_file import (
    BatchSaveRequest,
    BatchSaveResponse,
    FilterOptionsResponse,
    ParseBatchRequest,
    ParseBatchResponse,
    SqlFileCreateRequest,
    SqlFileDetail,
    SqlFileListResponse,
    SqlFileUpdateRequest,
)
from app.services.auth_service import CurrentUser
from app.services.cos_db_service import backup_sqlite_to_cos
from app.services.search_service import (
    SearchParams,
    get_filter_options,
    get_sql_file_by_id,
    search_sql_files,
)
from app.services.indexing_service import enqueue_index_job
from app.services.sql_crud_service import (
    batch_save,
    create_from_content,
    delete_sql,
    preview_parse,
    update_from_content,
)

router = APIRouter(prefix="/api/sql-files", tags=["sql-files"])


@router.post("/parse-batch", response_model=ParseBatchResponse)
def parse_batch(
    body: ParseBatchRequest,
    _user: CurrentUser = Depends(get_current_user),
) -> ParseBatchResponse:
    items = preview_parse([i.model_dump() for i in body.items])
    return ParseBatchResponse(items=items)


@router.post("/batch-save", response_model=BatchSaveResponse)
def save_batch(
    body: BatchSaveRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> BatchSaveResponse:
    result = batch_save(db, user.owner_email, [i.model_dump() for i in body.items])
    return BatchSaveResponse(**result)


@router.post("", response_model=SqlFileDetail)
def create_sql_file(
    body: SqlFileCreateRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SqlFileDetail:
    record, err, _is_update = create_from_content(
        db, user.owner_email, body.full_content, body.file_name
    )
    if err or not record:
        raise HTTPException(status_code=400, detail=err or "创建失败")
    db.flush()
    db.commit()
    backup_sqlite_to_cos()
    enqueue_index_job(db, user.owner_email, record.id, "upsert")
    db.commit()
    db.refresh(record)
    return SqlFileDetail.from_orm(record)


@router.get("", response_model=SqlFileListResponse)
def list_sql_files(
    keyword: str | None = Query(None),
    business: str | None = Query(None),
    scene: str | None = Query(None),
    tag: str | None = Query(None),
    core_table: str | None = Query(None),
    author: str | None = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SqlFileListResponse:
    params = SearchParams(
        keyword=keyword,
        business=business,
        scene=scene,
        tag=tag,
        core_table=core_table,
        author=author,
        page=page,
        page_size=page_size,
    )
    total, items = search_sql_files(db, params, user_email=user.owner_email)
    return SqlFileListResponse(total=total, list=items)


@router.get("/filter-options", response_model=FilterOptionsResponse)
def filter_options(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FilterOptionsResponse:
    return get_filter_options(db, user_email=user.owner_email)


@router.get("/{file_id}", response_model=SqlFileDetail)
def get_sql_file_detail(
    file_id: int,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SqlFileDetail:
    record = get_sql_file_by_id(db, file_id, user_email=user.owner_email)
    if not record:
        raise HTTPException(status_code=404, detail="SQL file not found")
    return SqlFileDetail.from_orm(record)


@router.put("/{file_id}", response_model=SqlFileDetail)
def update_sql_file(
    file_id: int,
    body: SqlFileUpdateRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SqlFileDetail:
    record, err = update_from_content(
        db, user.owner_email, file_id, body.full_content, body.file_name
    )
    if err or not record:
        raise HTTPException(status_code=400, detail=err or "更新失败")
    db.commit()
    backup_sqlite_to_cos()
    enqueue_index_job(db, user.owner_email, record.id, "upsert")
    db.commit()
    db.refresh(record)
    return SqlFileDetail.from_orm(record)


@router.delete("/{file_id}")
def remove_sql_file(
    file_id: int,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    if not delete_sql(db, user.owner_email, file_id):
        raise HTTPException(status_code=404, detail="SQL 不存在")
    enqueue_index_job(db, user.owner_email, file_id, "delete")
    db.commit()
    backup_sqlite_to_cos()
    return {"success": True}
