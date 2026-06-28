"""Database engine, session, and lightweight migrations."""

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import DATABASE_PATH, DATABASE_URL, SQLALCHEMY_DATABASE_URL

if not DATABASE_URL:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _migrate_legacy_schema() -> None:
    """Add columns for databases created before V3."""
    inspector = inspect(engine)
    tables = inspector.get_table_names()
    with engine.begin() as conn:
        if "sql_files" in tables:
            cols = {c["name"] for c in inspector.get_columns("sql_files")}
            if "user_email" not in cols:
                conn.execute(
                    text(
                        "ALTER TABLE sql_files ADD COLUMN user_email TEXT DEFAULT 'legacy'"
                    )
                )
                conn.execute(
                    text(
                        "UPDATE sql_files SET user_email = 'legacy' WHERE user_email IS NULL"
                    )
                )
        if "auth_sessions" in tables:
            cols = {c["name"] for c in inspector.get_columns("auth_sessions")}
            if "doris_user" not in cols:
                conn.execute(
                    text(
                        "ALTER TABLE auth_sessions ADD COLUMN doris_user TEXT DEFAULT ''"
                    )
                )
                conn.execute(
                    text(
                        "UPDATE auth_sessions SET doris_user = email WHERE doris_user IS NULL OR doris_user = ''"
                    )
                )


def _migrate_v4_semantic_agent() -> None:
    """Add index_status, indexing_jobs, conversations tables."""
    inspector = inspect(engine)
    tables = inspector.get_table_names()
    with engine.begin() as conn:
        if "sql_files" in tables:
            cols = {c["name"] for c in inspector.get_columns("sql_files")}
            if "index_status" not in cols:
                conn.execute(
                    text(
                        "ALTER TABLE sql_files ADD COLUMN index_status TEXT DEFAULT 'pending'"
                    )
                )
            if "index_error" not in cols:
                conn.execute(
                    text("ALTER TABLE sql_files ADD COLUMN index_error TEXT")
                )
            if "indexed_at" not in cols:
                conn.execute(
                    text("ALTER TABLE sql_files ADD COLUMN indexed_at DATETIME")
                )
            conn.execute(
                text(
                    "UPDATE sql_files SET index_status = 'pending' "
                    "WHERE index_status IS NULL OR index_status = ''"
                )
            )


def dispose_engine() -> None:
    """Drop pooled connections after replacing the SQLite file on disk."""
    engine.dispose()


def init_db() -> None:
    from app.models import auth_session, conversation, indexing_job, sql_file  # noqa: F401
    from app.migrate_sql_files import migrate_sql_files_table

    Base.metadata.create_all(bind=engine)
    _migrate_legacy_schema()
    migrate_sql_files_table()
    _migrate_v4_semantic_agent()
