from datetime import datetime, timedelta
import time
from typing import Optional

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

import config
from data.user_auth import user_auth, UserRecord

security = HTTPBearer()

_RATE_LIMITS: dict[str, list[float]] = {}
_RATE_WINDOW_SECONDS = 60
_RATE_MAX_PER_WINDOW = 5

_FAILED_LOGINS: dict[str, list[float]] = {}
_LOGIN_LOCKS: dict[str, float] = {}
_LOCKOUT_WINDOW_SECONDS = 600
_LOCKOUT_THRESHOLD = 5
_LOCKOUT_DURATION_SECONDS = 600


def _check_rate_limit(request: Request, key: str) -> None:
    now = time.time()
    window_start = now - _RATE_WINDOW_SECONDS
    entries = _RATE_LIMITS.get(key, [])
    entries = [t for t in entries if t >= window_start]
    if len(entries) >= _RATE_MAX_PER_WINDOW:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many requests")
    entries.append(now)
    _RATE_LIMITS[key] = entries


def check_auth_rate_limit(request: Request, action: str, phone: str | None = None) -> None:
    client_ip = request.client.host if request.client else "unknown"
    suffix = phone or "none"
    key = f"{action}:{client_ip}:{suffix}"
    _check_rate_limit(request, key)


def _login_key(request: Request, phone: str) -> str:
    client_ip = request.client.host if request.client else "unknown"
    return f"{client_ip}:{phone}"


def is_login_locked(request: Request, phone: str) -> bool:
    key = _login_key(request, phone)
    locked_until = _LOGIN_LOCKS.get(key)
    if not locked_until:
        return False
    if time.time() >= locked_until:
        _LOGIN_LOCKS.pop(key, None)
        _FAILED_LOGINS.pop(key, None)
        return False
    return True


def record_login_failure(request: Request, phone: str) -> None:
    key = _login_key(request, phone)
    now = time.time()
    window_start = now - _LOCKOUT_WINDOW_SECONDS
    entries = _FAILED_LOGINS.get(key, [])
    entries = [t for t in entries if t >= window_start]
    entries.append(now)
    _FAILED_LOGINS[key] = entries
    if len(entries) >= _LOCKOUT_THRESHOLD:
        _LOGIN_LOCKS[key] = now + _LOCKOUT_DURATION_SECONDS


def clear_login_failures(request: Request, phone: str) -> None:
    key = _login_key(request, phone)
    _FAILED_LOGINS.pop(key, None)
    _LOGIN_LOCKS.pop(key, None)


class RegisterRequest(BaseModel):
    phone: str
    password: str
    email: str


class LoginRequest(BaseModel):
    phone: str
    password: str


class EmailCodeRequest(BaseModel):
    phone: str
    email: str
    password: str


class EmailCodeVerify(BaseModel):
    phone: str
    code: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


def create_access_token(user: UserRecord, expires_minutes: Optional[int] = None) -> str:
    expire = datetime.utcnow() + timedelta(minutes=expires_minutes or config.API_TOKEN_EXPIRE_MINUTES)
    payload = {"sub": str(user.user_id), "phone": user.phone, "exp": expire}
    return jwt.encode(payload, config.API_SECRET, algorithm="HS256")


def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> UserRecord:
    token = credentials.credentials
    try:
        payload = jwt.decode(token, config.API_SECRET, algorithms=["HS256"])
        user_id = int(payload.get("sub"))
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user = user_auth.get_by_id(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    if request is not None:
        request.state.user_id = user.user_id
        request.state.user_phone = user.phone
    return user
