"""Shared group membership and access control."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from app.config import SHARED_GROUP_NAME, SUPER_ADMIN_EMAIL
from app.models.shared_group import SharedGroup, SharedGroupMember


class SharedGroupAccessError(PermissionError):
    pass


def ensure_default_group(db: Session) -> SharedGroup:
    group = db.query(SharedGroup).order_by(SharedGroup.id.asc()).first()
    if group:
        return group
    owner = SUPER_ADMIN_EMAIL.lower()
    group = SharedGroup(name=SHARED_GROUP_NAME, owner_email=owner)
    db.add(group)
    db.flush()
    db.add(
        SharedGroupMember(
            group_id=group.id,
            email=owner,
            role="owner",
            status="approved",
            approved_at=datetime.utcnow(),
        )
    )
    db.commit()
    db.refresh(group)
    return group


def get_default_group(db: Session) -> SharedGroup:
    return ensure_default_group(db)


def is_group_owner(email: str, group: SharedGroup) -> bool:
    return email.lower() == group.owner_email.lower()


def get_membership(
    db: Session, email: str, group_id: int | None = None
) -> SharedGroupMember | None:
    group = get_default_group(db) if group_id is None else db.query(SharedGroup).get(group_id)
    if not group:
        return None
    gid = group.id
    return (
        db.query(SharedGroupMember)
        .filter(SharedGroupMember.group_id == gid, SharedGroupMember.email == email.lower())
        .first()
    )


def is_approved_member(db: Session, email: str) -> bool:
    if email.lower() == SUPER_ADMIN_EMAIL.lower():
        ensure_default_group(db)
        return True
    m = get_membership(db, email.lower())
    return m is not None and m.status == "approved"


def require_approved_member(db: Session, email: str) -> SharedGroupMember:
    ensure_default_group(db)
    if email.lower() == SUPER_ADMIN_EMAIL.lower():
        group = get_default_group(db)
        m = get_membership(db, email.lower(), group.id)
        if m and m.status == "approved":
            return m
        db.add(
            SharedGroupMember(
                group_id=group.id,
                email=email.lower(),
                role="owner",
                status="approved",
                approved_at=datetime.utcnow(),
            )
        )
        db.commit()
        return get_membership(db, email.lower(), group.id)  # type: ignore[return-value]
    m = get_membership(db, email.lower())
    if not m or m.status != "approved":
        raise SharedGroupAccessError("您尚未加入共享群或申请未通过，请先申请入群")
    return m


def require_owner(db: Session, email: str) -> SharedGroup:
    group = get_default_group(db)
    if not is_group_owner(email, group):
        raise SharedGroupAccessError("仅群主（超级管理员）可执行此操作")
    return group


def request_join(db: Session, email: str) -> SharedGroupMember:
    group = ensure_default_group(db)
    email = email.lower()
    if is_group_owner(email, group):
        existing = get_membership(db, email, group.id)
        if existing:
            return existing
    existing = get_membership(db, email, group.id)
    if existing:
        if existing.status == "approved":
            return existing
        if existing.status == "pending":
            return existing
        existing.status = "pending"
        existing.approved_at = None
        db.commit()
        db.refresh(existing)
        return existing
    member = SharedGroupMember(group_id=group.id, email=email, role="member", status="pending")
    db.add(member)
    db.commit()
    db.refresh(member)
    return member


def approve_member(db: Session, owner_email: str, member_email: str) -> SharedGroupMember:
    group = require_owner(db, owner_email)
    member = (
        db.query(SharedGroupMember)
        .filter(
            SharedGroupMember.group_id == group.id,
            SharedGroupMember.email == member_email.lower(),
        )
        .first()
    )
    if not member:
        raise ValueError("成员不存在")
    member.status = "approved"
    member.approved_at = datetime.utcnow()
    db.commit()
    db.refresh(member)
    return member


def remove_member(db: Session, owner_email: str, member_email: str) -> None:
    group = require_owner(db, owner_email)
    if member_email.lower() == group.owner_email.lower():
        raise ValueError("不能移除群主")
    member = (
        db.query(SharedGroupMember)
        .filter(
            SharedGroupMember.group_id == group.id,
            SharedGroupMember.email == member_email.lower(),
        )
        .first()
    )
    if member:
        db.delete(member)
        db.commit()


def list_members(
    db: Session, requester_email: str, status: str | None = None
) -> list[SharedGroupMember]:
    group = get_default_group(db)
    require_owner(db, requester_email)
    q = db.query(SharedGroupMember).filter(SharedGroupMember.group_id == group.id)
    if status:
        q = q.filter(SharedGroupMember.status == status)
    return q.order_by(SharedGroupMember.created_at.desc()).all()


def membership_status(db: Session, email: str) -> dict:
    group = ensure_default_group(db)
    m = get_membership(db, email.lower(), group.id)
    return {
        "group_id": group.id,
        "group_name": group.name,
        "owner_email": group.owner_email,
        "is_owner": is_group_owner(email, group),
        "status": m.status if m else None,
        "role": m.role if m else None,
        "can_access": is_approved_member(db, email),
    }
