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
)
from api.routes import report, contacts
from data.user_auth import user_auth
import config

logging.basicConfig(level=logging.WARNING)
app = FastAPI(title="DocBotApp API")
logger = logging.getLogger("docbot.api")

origins = [o.strip() for o in config.CORS_ORIGINS.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
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
def register(payload: RegisterRequest):
    try:
        user = user_auth.create_user(payload.phone, payload.password, email=payload.email)
    except ValueError:
        raise HTTPException(status_code=400, detail="User already exists")
    token = create_access_token(user)
    return TokenResponse(access_token=token)


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest):
    user = user_auth.get_by_phone(payload.phone)
    if not user or not user_auth.verify_password(user, payload.password):
        raise HTTPException(status_code=401, detail="Invalid phone or password")
    if not user.verified:
        raise HTTPException(status_code=401, detail="Email not verified")
    token = create_access_token(user)
    return TokenResponse(access_token=token)


@app.post("/auth/request_email_code")
def request_email_code(payload: EmailCodeRequest):
    try:
        user_auth.request_email_code(payload.phone, payload.email, payload.password)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"status": "ok"}


@app.post("/auth/verify_email", response_model=TokenResponse)
def verify_email(payload: EmailCodeVerify):
    try:
        user = user_auth.verify_email_code(payload.phone, payload.code)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    token = create_access_token(user)
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
