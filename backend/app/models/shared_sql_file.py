"""Shared SQL files in the org-wide group library."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class SharedSqlFile(Base):
    __tablename__ = "shared_sql_files"
    __table_args__ = (UniqueConstraint("group_id", "file_name", name="uq_shared_group_file"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    group_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    uploaded_by: Mapped[str] = mapped_column(Text, nullable=False)

    file_name: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    file_path: Mapped[str | None] = mapped_column(Text, nullable=True)

    metric_raw: Mapped[str | None] = mapped_column(Text, nullable=True)
    metrics_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    business: Mapped[str | None] = mapped_column(Text, nullable=True)
    scene: Mapped[str | None] = mapped_column(Text, nullable=True)
    tag_raw: Mapped[str | None] = mapped_column(Text, nullable=True)
    tags_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    dimension_raw: Mapped[str | None] = mapped_column(Text, nullable=True)
    dimensions_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    core_table_raw: Mapped[str | None] = mapped_column(Text, nullable=True)
    core_tables_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    author_raw: Mapped[str | None] = mapped_column(Text, nullable=True)
    authors_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    sql_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    comment_block: Mapped[str | None] = mapped_column(Text, nullable=True)

    storage_mode: Mapped[str] = mapped_column(
        Text, nullable=False, default="public"
    )  # public | encrypted
    is_public: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    index_status: Mapped[str] = mapped_column(Text, nullable=False, default="pending")
    index_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    indexed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )
