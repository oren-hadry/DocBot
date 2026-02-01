import logging
import time
from uuid import uuid4

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

from api.auth import (
    RegisterRequest,
    LoginRequest,
    TokenResponse,
    create_access_token,
    EmailCodeRequest,
    EmailCodeVerify,
    get_current_user,
    check_auth_rate_limit,
    is_login_locked,
    record_login_failure,
    clear_login_failures,
)
from api.routes import report, contacts
from data.user_auth import user_auth
from data.audit_log import log_event
import config

logging.basicConfig(level=logging.WARNING)
app = FastAPI(title="DocBotApp API")
logger = logging.getLogger("docbot.api")

origins = [o.strip() for o in config.CORS_ORIGINS.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def request_logging(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or uuid4().hex
    request.state.request_id = request_id
    start = time.time()
    response = None
    try:
        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response
    finally:
        duration_ms = int((time.time() - start) * 1000)
        user_id = getattr(request.state, "user_id", None)
        user_phone = getattr(request.state, "user_phone", None)
        status_code = getattr(response, "status_code", 500)
        logger.info(
            "request_id=%s user_id=%s phone=%s method=%s path=%s status=%s duration_ms=%s",
            request_id,
            user_id,
            user_phone,
            request.method,
            request.url.path,
            status_code,
            duration_ms,
        )


@app.middleware("http")
async def ensure_json_utf8(request: Request, call_next):
    response = await call_next(request)
    content_type = response.headers.get("content-type")
    if content_type and content_type.startswith("application/json") and "charset=" not in content_type:
        response.headers["content-type"] = f"{content_type}; charset=utf-8"
    return response


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/register", response_model=TokenResponse)
def register(payload: RegisterRequest, request: Request):
    check_auth_rate_limit(request, "register", payload.phone)
    try:
        user = user_auth.create_user(payload.phone, payload.password, email=payload.email)
    except ValueError:
        raise HTTPException(status_code=400, detail="User already exists")
    token = create_access_token(user)
    log_event(user.user_id, "REGISTER", {"phone": user.phone, "email": user.email})
    return TokenResponse(access_token=token)


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, request: Request):
    check_auth_rate_limit(request, "login", payload.phone)
    if is_login_locked(request, payload.phone):
        raise HTTPException(status_code=429, detail="Too many failed attempts")
    user = user_auth.get_by_phone(payload.phone)
    if not user or not user_auth.verify_password(user, payload.password):
        record_login_failure(request, payload.phone)
        if user:
            log_event(user.user_id, "LOGIN_FAILED", {"phone": payload.phone})
        raise HTTPException(status_code=401, detail="Invalid phone or password")
    if not user.verified:
        raise HTTPException(status_code=401, detail="Email not verified")
    clear_login_failures(request, payload.phone)
    token = create_access_token(user)
    log_event(user.user_id, "LOGIN_SUCCESS", {"phone": user.phone})
    return TokenResponse(access_token=token)


@app.post("/auth/request_email_code")
def request_email_code(payload: EmailCodeRequest, request: Request):
    check_auth_rate_limit(request, "request_email_code", payload.phone)
    try:
        user_auth.request_email_code(payload.phone, payload.email, payload.password)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    user = user_auth.get_by_phone(payload.phone)
    if user:
        log_event(user.user_id, "REQUEST_EMAIL_CODE", {"phone": user.phone, "email": payload.email})
    return {"status": "ok"}


@app.post("/auth/verify_email", response_model=TokenResponse)
def verify_email(payload: EmailCodeVerify, request: Request):
    check_auth_rate_limit(request, "verify_email", payload.phone)
    try:
        user = user_auth.verify_email_code(payload.phone, payload.code)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    token = create_access_token(user)
    log_event(user.user_id, "VERIFY_EMAIL", {"phone": user.phone, "email": user.email})
    return TokenResponse(access_token=token)


@app.get("/auth/me")
def get_me(user=Depends(get_current_user)):
    return {
        "user_id": user.user_id,
        "phone": user.phone,
        "email": user.email,
        "verified": user.verified,
    }


app.include_router(report.router, prefix="/reports", tags=["reports"])
app.include_router(contacts.router, prefix="/contacts", tags=["contacts"])
