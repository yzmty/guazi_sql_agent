"""Shared SQL group REST API."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.database import get_db
from app.schemas.sql_file import FilterOptionsResponse
from app.schemas.shared_group import (
    MemberActionRequest,
    SharedGroupMemberItem,
    SharedGroupMemberListResponse,
    SharedGroupStatusResponse,
    SharedSqlBatchSaveRequest,
    SharedSqlBatchSaveResponse,
    SharedSqlCreateRequest,
    SharedSqlDetail,
    SharedSqlListItem,
    SharedSqlListResponse,
)
from app.services.auth_service import CurrentUser
from app.services.shared_group_service import (
    SharedGroupAccessError,
    approve_member,
    list_members,
    membership_status,
    remove_member,
    request_join,
)
from app.services.shared_sql_service import (
    batch_save_shared,
    create_shared_sql,
    delete_shared_sql,
    get_shared_filter_options,
    get_shared_sql,
    list_shared_sql,
    shared_sql_detail_dict,
)
from app.services.search_service import SearchParams
from app.utils.text_utils import parse_json_list

router = APIRouter(prefix="/api/shared-group", tags=["shared-group"])


def _to_list_item(record) -> SharedSqlListItem:
    return SharedSqlListItem(
        id=record.id,
        file_name=record.file_name,
        business=record.business,
        scene=record.scene,
        metrics=parse_json_list(record.metrics_json),
        tags=parse_json_list(record.tags_json),
        dimensions=parse_json_list(record.dimensions_json),
        core_tables=parse_json_list(record.core_tables_json),
        authors=parse_json_list(record.authors_json),
        description=record.description,
        storage_mode=record.storage_mode,
        is_public=record.is_public,
        uploaded_by=record.uploaded_by,
        index_status=record.index_status,
    )


@router.get("/status", response_model=SharedGroupStatusResponse)
def group_status(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedGroupStatusResponse:
    return SharedGroupStatusResponse(**membership_status(db, user.owner_email))


@router.post("/join", response_model=SharedGroupStatusResponse)
def join_group(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedGroupStatusResponse:
    request_join(db, user.owner_email)
    return SharedGroupStatusResponse(**membership_status(db, user.owner_email))


@router.get("/members", response_model=SharedGroupMemberListResponse)
def get_members(
    status: str | None = Query(None),
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedGroupMemberListResponse:
    try:
        rows = list_members(db, user.owner_email, status=status)
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    return SharedGroupMemberListResponse(
        items=[
            SharedGroupMemberItem(
                id=m.id,
                email=m.email,
                role=m.role,
                status=m.status,
                created_at=m.created_at,
                approved_at=m.approved_at,
            )
            for m in rows
        ]
    )


@router.post("/members/approve", response_model=SharedGroupMemberItem)
def approve_group_member(
    body: MemberActionRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        member = approve_member(db, user.owner_email, body.email)
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return SharedGroupMemberItem(
        id=member.id,
        email=member.email,
        role=member.role,
        status=member.status,
        created_at=member.created_at,
        approved_at=member.approved_at,
    )


@router.post("/members/remove")
def remove_group_member(
    body: MemberActionRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        remove_member(db, user.owner_email, body.email)
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"success": True}


@router.get("/sql-files/filter-options", response_model=FilterOptionsResponse)
def shared_filter_options(
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FilterOptionsResponse:
    try:
        return get_shared_filter_options(db, user.owner_email)
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc


@router.get("/sql-files", response_model=SharedSqlListResponse)
def list_group_sql(
    keyword: str | None = Query(None),
    business: str | None = Query(None),
    scene: str | None = Query(None),
    tag: str | None = Query(None),
    core_table: str | None = Query(None),
    author: str | None = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(100, ge=1, le=200),
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedSqlListResponse:
    try:
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
        total, rows = list_shared_sql(db, user.owner_email, params=params)
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    return SharedSqlListResponse(total=total, list=[_to_list_item(r) for r in rows])


@router.get("/sql-files/{file_id}", response_model=SharedSqlDetail)
def get_group_sql_detail(
    file_id: int,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedSqlDetail:
    try:
        record = get_shared_sql(db, user.owner_email, file_id)
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if not record:
        raise HTTPException(status_code=404, detail="SQL 不存在")
    data = shared_sql_detail_dict(record)
    return SharedSqlDetail(**data)


@router.post("/sql-files", response_model=SharedSqlDetail)
def create_group_sql(
    body: SharedSqlCreateRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedSqlDetail:
    try:
        record, err = create_shared_sql(
            db,
            user.owner_email,
            body.full_content,
            body.file_name,
            storage_mode=body.storage_mode,
            is_public=body.is_public,
        )
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if err or not record:
        raise HTTPException(status_code=400, detail=err or "创建失败")
    return SharedSqlDetail(**shared_sql_detail_dict(record))


@router.post("/sql-files/batch-save", response_model=SharedSqlBatchSaveResponse)
def batch_save_group_sql(
    body: SharedSqlBatchSaveRequest,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedSqlBatchSaveResponse:
    try:
        result = batch_save_shared(
            db, user.owner_email, [i.model_dump() for i in body.items]
        )
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    return SharedSqlBatchSaveResponse(**result)


@router.delete("/sql-files/{file_id}")
def delete_group_sql(
    file_id: int,
    user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        ok = delete_shared_sql(db, user.owner_email, file_id)
    except SharedGroupAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if not ok:
        raise HTTPException(status_code=404, detail="SQL 不存在")
    return {"success": True}
