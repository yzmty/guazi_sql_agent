import sqlite3
from pathlib import Path

db = Path("data/sql_agent.db")
conn = sqlite3.connect(db)
for row in conn.execute(
    "SELECT name, sql FROM sqlite_master WHERE tbl_name='sql_files'"
):
    print(row)
conn.close()
