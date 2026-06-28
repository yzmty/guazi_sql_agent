"""One-off migration helper for sql_files table schema."""

from sqlalchemy import inspect, text

from app.database import engine


def migrate_sql_files_table() -> None:
    """
    Rebuild sql_files when legacy UNIQUE(file_name) blocks per-user imports.
    Safe to run multiple times.
    """
    inspector = inspect(engine)
    if "sql_files" not in inspector.get_table_names():
        return

    indexes = {idx["name"]: idx for idx in inspector.get_indexes("sql_files")}
    has_user_file_uq = "uq_user_file" in indexes
    legacy_file_name_uq = any(
        idx.get("unique") and idx.get("column_names") == ["file_name"]
        for idx in indexes.values()
    )

    if has_user_file_uq and not legacy_file_name_uq:
        return

    with engine.begin() as conn:
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS sql_files_v3 (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_email TEXT NOT NULL,
                    file_name TEXT NOT NULL,
                    file_path TEXT,
                    metric_raw TEXT,
                    metrics_json TEXT,
                    business TEXT,
                    scene TEXT,
                    tag_raw TEXT,
                    tags_json TEXT,
                    dimension_raw TEXT,
                    dimensions_json TEXT,
                    core_table_raw TEXT,
                    core_tables_json TEXT,
                    author_raw TEXT,
                    authors_json TEXT,
                    description TEXT,
                    sql_content TEXT,
                    comment_block TEXT,
                    index_status TEXT DEFAULT 'pending',
                    index_error TEXT,
                    indexed_at DATETIME,
                    created_at DATETIME,
                    updated_at DATETIME,
                    CONSTRAINT uq_user_file UNIQUE (user_email, file_name)
                )
                """
            )
        )
        conn.execute(
            text(
                """
                INSERT OR IGNORE INTO sql_files_v3 (
                    id, user_email, file_name, file_path,
                    metric_raw, metrics_json, business, scene,
                    tag_raw, tags_json, dimension_raw, dimensions_json,
                    core_table_raw, core_tables_json, author_raw, authors_json,
                    description, sql_content, comment_block,
                    index_status, index_error, indexed_at,
                    created_at, updated_at
                )
                SELECT
                    id,
                    COALESCE(user_email, 'legacy'),
                    file_name,
                    COALESCE(file_path, ''),
                    metric_raw, metrics_json, business, scene,
                    tag_raw, tags_json, dimension_raw, dimensions_json,
                    core_table_raw, core_tables_json, author_raw, authors_json,
                    description, sql_content, comment_block,
                    'pending', NULL, NULL,
                    created_at, updated_at
                FROM sql_files
                """
            )
        )
        conn.execute(text("DROP TABLE sql_files"))
        conn.execute(text("ALTER TABLE sql_files_v3 RENAME TO sql_files"))
        conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_sql_files_user_email ON sql_files (user_email)")
        )
        conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_sql_files_file_name ON sql_files (file_name)")
        )
