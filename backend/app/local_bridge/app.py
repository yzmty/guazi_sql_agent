"""FastAPI app: local Doris proxy for the cloud-hosted guazi_sql_agent UI."""

from __future__ import annotations

from urllib.parse import quote

from fastapi import FastAPI, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.local_bridge.credentials import (
    clear_credentials,
    credentials_status,
    load_credentials,
    save_credentials,
)
from app.services.doris_service import (
    CredentialCheckResult,
    SqlExecutionError,
    apply_sql_params,
    check_credentials as doris_check_credentials,
    detect_dollar_params,
    execute_query,
    normalize_doris_username,
    normalize_login_email,
    validate_credentials,
)
from app.config import LOCAL_BRIDGE_LOGIN_SECRET
from app.local_bridge.local_login_page import (
    DEFAULT_CLOUD_LOGIN,
    is_allowed_return_url,
    render_local_login_page,
)
from app.services.local_bridge_proof import PROOF_TTL_SECONDS, create_login_proof

app = FastAPI(title="Guazi SQL Local Doris Bridge", version="1.0.0")


class PrivateNetworkAccessMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        response.headers["Access-Control-Allow-Private-Network"] = "true"
        return response


app.add_middleware(PrivateNetworkAccessMiddleware)
# Binds to 127.0.0.1 only; permissive CORS so the CloudBase page can call localhost.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class CredentialsRequest(BaseModel):
    user: str = Field(..., min_length=1, description="Doris 用户名（通常为邮箱）")
    password: str = Field(..., min_length=1)


class DetectParamsRequest(BaseModel):
    sql: str


class DetectParamsResponse(BaseModel):
    params: list[str]


class ExecuteSqlRequest(BaseModel):
    sql: str
    start_date: str
    end_date: str
    params: dict[str, str] = Field(default_factory=dict)


class ExecuteSqlResponse(BaseModel):
    columns: list[str]
    rows: list[list]
    row_count: int
    truncated: bool
    executed_sql: str


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}


@app.get("/login", response_class=HTMLResponse)
def local_login_form(return_url: str = DEFAULT_CLOUD_LOGIN) -> HTMLResponse:
    if not is_allowed_return_url(return_url):
        return_url = DEFAULT_CLOUD_LOGIN
    return HTMLResponse(render_local_login_page(return_url))


@app.post("/login")
def local_login_submit(
    user: str = Form(...),
    password: str = Form(...),
    return_url: str = Form(DEFAULT_CLOUD_LOGIN),
) -> RedirectResponse:
    if not is_allowed_return_url(return_url):
        return_url = DEFAULT_CLOUD_LOGIN

    email = normalize_login_email(user)
    doris_user = normalize_doris_username(user)
    check = doris_check_credentials(user, password)
    if check == CredentialCheckResult.NETWORK_ERROR:
        err = quote("无法连接 Doris，请先连接公司 VPN")
        return RedirectResponse(
            f"/login?return_url={quote(return_url, safe='')}&error={err}",
            status_code=303,
        )
    if check != CredentialCheckResult.OK:
        err = quote("Doris 账号或密码错误，请确认 Adhoc 查数密码正确")
        return RedirectResponse(
            f"/login?return_url={quote(return_url, safe='')}&error={err}",
            status_code=303,
        )

    save_credentials(doris_user, password)
    proof = create_login_proof(email, LOCAL_BRIDGE_LOGIN_SECRET)
    sep = "&" if "?" in return_url else "?"
    target = (
        f"{return_url}{sep}bridge_email={quote(email.lower())}"
        f"&bridge_proof={quote(proof)}"
    )
    return RedirectResponse(target, status_code=303)


@app.get("/credentials/status")
def get_credentials_status() -> dict[str, object]:
    return credentials_status()


@app.post("/credentials")
def set_credentials(body: CredentialsRequest) -> dict[str, object]:
    if not validate_credentials(body.user.strip(), body.password):
        raise HTTPException(status_code=400, detail="Doris 账号或密码错误，请确认已连接 VPN")
    save_credentials(body.user, body.password)
    return credentials_status()


@app.post("/credentials/login-proof")
def issue_login_proof(body: CredentialsRequest) -> dict[str, object]:
    user = body.user.strip()
    check = doris_check_credentials(user, body.password)
    if check == CredentialCheckResult.NETWORK_ERROR:
        raise HTTPException(
            status_code=400,
            detail="无法连接 Doris，请先连接公司 VPN 后再登录",
        )
    if check != CredentialCheckResult.OK:
        raise HTTPException(
            status_code=400,
            detail="Doris 账号或密码错误，请确认 Adhoc 查数密码正确",
        )
    return {
        "proof": create_login_proof(user, LOCAL_BRIDGE_LOGIN_SECRET),
        "expires_in": PROOF_TTL_SECONDS,
    }


@app.delete("/credentials")
def remove_credentials() -> dict[str, bool]:
    clear_credentials()
    return {"ok": True}


@app.post("/detect-params", response_model=DetectParamsResponse)
def detect_params(body: DetectParamsRequest) -> DetectParamsResponse:
    return DetectParamsResponse(params=detect_dollar_params(body.sql))


@app.post("/execute", response_model=ExecuteSqlResponse)
def run_sql(body: ExecuteSqlRequest) -> ExecuteSqlResponse:
    creds = load_credentials()
    if not creds:
        raise HTTPException(status_code=401, detail="请先配置本地 Doris 账号")

    sql = body.sql.strip()
    if not sql:
        raise HTTPException(status_code=400, detail="SQL 不能为空")

    user, password = creds
    try:
        final_sql = apply_sql_params(
            sql,
            body.start_date.strip(),
            body.end_date.strip(),
            body.params,
        )
        result = execute_query(user, password, final_sql)
        return ExecuteSqlResponse(executed_sql=final_sql, **result)
    except SqlExecutionError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
