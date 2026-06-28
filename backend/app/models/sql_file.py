"""SQLAlchemy model for user-scoped SQL knowledge entries."""

from datetime import datetime

from sqlalchemy import DateTime, Integer, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class SqlFile(Base):
    __tablename__ = "sql_files"
    __table_args__ = (UniqueConstraint("user_email", "file_name", name="uq_user_file"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_email: Mapped[str] = mapped_column(Text, nullable=False, index=True)
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

    index_status: Mapped[str] = mapped_column(Text, nullable=False, default="pending")
    index_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    indexed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )
