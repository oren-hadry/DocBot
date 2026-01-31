from datetime import datetime, timedelta
from typing import Optional

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

import config
from data.user_auth import user_auth, UserRecord

security = HTTPBearer()


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
