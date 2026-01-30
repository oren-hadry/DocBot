from fastapi import FastAPI, HTTPException

from api.auth import RegisterRequest, LoginRequest, TokenResponse, create_access_token
from api.routes import report, contacts
from data.user_auth import user_auth

app = FastAPI(title="DocBotApp API")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/register", response_model=TokenResponse)
def register(payload: RegisterRequest):
    try:
        user = user_auth.create_user(payload.phone, payload.password)
    except ValueError:
        raise HTTPException(status_code=400, detail="User already exists")
    token = create_access_token(user)
    return TokenResponse(access_token=token)


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest):
    user = user_auth.get_by_phone(payload.phone)
    if not user or not user_auth.verify_password(user, payload.password):
        raise HTTPException(status_code=401, detail="Invalid phone or password")
    token = create_access_token(user)
    return TokenResponse(access_token=token)


app.include_router(report.router, prefix="/reports", tags=["reports"])
app.include_router(contacts.router, prefix="/contacts", tags=["contacts"])
