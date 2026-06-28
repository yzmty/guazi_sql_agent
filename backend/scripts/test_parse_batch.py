import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient

from app.database import SessionLocal, init_db
from app.main import app
from app.services.auth_service import login

init_db()
client = TestClient(app)
db = SessionLocal()
try:
    token, _ = login(db, "yangyuefang@guazi.com", "Yyf010103")
finally:
    db.close()

headers = {"Authorization": f"Bearer {token}"}
sample = "/*\nfile:test.sql,\n指标:NU\n业务:C1\n*/\nSELECT 1"
r = client.post(
    "/api/sql-files/parse-batch",
    json={"items": [{"file_name": "t.sql", "full_content": sample}]},
    headers=headers,
)
print("status", r.status_code)
print(r.text[:1000])
