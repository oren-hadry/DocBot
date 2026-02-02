import json
import logging
import re
import secrets
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from passlib.context import CryptContext

import config

logger = logging.getLogger(__name__)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


@dataclass
class UserRecord:
    user_id: int
    phone: str
    email: Optional[str]
    password_hash: str
    created_at: str
    verified: bool = False
    verification_code_hash: Optional[str] = None
    verification_expires_at: Optional[str] = None
    full_name: Optional[str] = None
    role_title: Optional[str] = None
    phone_contact: Optional[str] = None
    company_name: Optional[str] = None
    signature_path: Optional[str] = None
    logo_path: Optional[str] = None


class UserAuthManager:
    def __init__(self):
        self._cache: dict[str, UserRecord] = {}

    def _load_all(self) -> dict[str, UserRecord]:
        if self._cache:
            return self._cache
        users_file = config.USERS_FILE
        users_file.parent.mkdir(parents=True, exist_ok=True)
        if users_file.exists():
            try:
                with open(users_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                normalized = {}
                for u in data:
                    normalized[u["phone"]] = UserRecord(
                        user_id=u["user_id"],
                        phone=u["phone"],
                        email=u.get("email"),
                        password_hash=u["password_hash"],
                        created_at=u.get("created_at", datetime.utcnow().isoformat(timespec="seconds") + "Z"),
                        verified=u.get("verified", False),
                        verification_code_hash=u.get("verification_code_hash"),
                        verification_expires_at=u.get("verification_expires_at"),
                        full_name=u.get("full_name"),
                        role_title=u.get("role_title"),
                        phone_contact=u.get("phone_contact"),
                        company_name=u.get("company_name"),
                        signature_path=u.get("signature_path"),
                        logo_path=u.get("logo_path"),
                    )
                self._cache = normalized
                return self._cache
            except Exception as e:
                logger.error(f"Failed to load users: {e}")
        self._cache = {}
        return self._cache

    def _save_all(self, users: dict[str, UserRecord]) -> None:
        users_file = config.USERS_FILE
        users_file.parent.mkdir(parents=True, exist_ok=True)
        with open(users_file, "w", encoding="utf-8") as f:
            json.dump([asdict(u) for u in users.values()], f, ensure_ascii=False, indent=2)
        self._cache = users

    def _next_user_id(self, users: dict[str, UserRecord]) -> int:
        if not users:
            return 1
        max_id = max(u.user_id for u in users.values())
        return max_id + 1

    def get_by_phone(self, phone: str) -> Optional[UserRecord]:
        users = self._load_all()
        return users.get(phone)

    def get_by_id(self, user_id: int) -> Optional[UserRecord]:
        users = self._load_all()
        for user in users.values():
            if user.user_id == user_id:
                return user
        return None

    def create_user(self, phone: str, password: str, email: Optional[str] = None) -> UserRecord:
        users = self._load_all()
        if phone in users:
            raise ValueError("User already exists")
        password_hash = pwd_context.hash(password)
        user = UserRecord(
            user_id=self._next_user_id(users),
            phone=phone,
            email=email,
            password_hash=password_hash,
            created_at=datetime.utcnow().isoformat(timespec="seconds") + "Z",
            verified=False,
        )
        users[phone] = user
        self._save_all(users)
        return user

    def verify_password(self, user: UserRecord, password: str) -> bool:
        return pwd_context.verify(password, user.password_hash)

    def request_email_code(self, phone: str, email: str, password: str) -> None:
        if not self._is_valid_email(email):
            raise ValueError("Invalid email")
        users = self._load_all()
        user = users.get(phone)
        if user and user.verified:
            raise ValueError("User already verified")
        if user and not self.verify_password(user, password):
            raise ValueError("Invalid password")
        if not user:
            user = self.create_user(phone, password, email=email)
        else:
            user.email = email
            user.password_hash = pwd_context.hash(password)
        code = f"{secrets.randbelow(1000000):06d}"
        user.verification_code_hash = pwd_context.hash(code)
        expires_at = datetime.utcnow() + timedelta(minutes=10)
        user.verification_expires_at = expires_at.isoformat(timespec="seconds") + "Z"
        users[phone] = user
        self._save_all(users)
        self._send_email_code(email, code)

    def verify_email_code(self, phone: str, code: str) -> UserRecord:
        users = self._load_all()
        user = users.get(phone)
        if not user or not user.verification_code_hash:
            raise ValueError("No verification requested")
        if user.verification_expires_at and datetime.utcnow() > self._parse_time(user.verification_expires_at):
            raise ValueError("Code expired")
        if not pwd_context.verify(code, user.verification_code_hash):
            raise ValueError("Invalid code")
        user.verified = True
        user.verification_code_hash = None
        user.verification_expires_at = None
        users[phone] = user
        self._save_all(users)
        return user

    def update_profile(
        self,
        user_id: int,
        full_name: Optional[str] = None,
        role_title: Optional[str] = None,
        phone_contact: Optional[str] = None,
        company_name: Optional[str] = None,
        signature_path: Optional[str] = None,
        logo_path: Optional[str] = None,
    ) -> UserRecord:
        users = self._load_all()
        user = None
        for u in users.values():
            if u.user_id == user_id:
                user = u
                break
        if not user:
            raise ValueError("User not found")
        if full_name is not None:
            user.full_name = full_name
        if role_title is not None:
            user.role_title = role_title
        if phone_contact is not None:
            user.phone_contact = phone_contact
        if company_name is not None:
            user.company_name = company_name
        if signature_path is not None:
            user.signature_path = signature_path
        if logo_path is not None:
            user.logo_path = logo_path
        self._save_all(users)
        return user

    def _send_email_code(self, email: str, code: str) -> None:
        import smtplib
        from email.message import EmailMessage

        host = config.SMTP_HOST
        if not host:
            logger.warning("SMTP not configured; verification code: %s", code)
            return
        port = config.SMTP_PORT
        msg = EmailMessage()
        msg["Subject"] = "Your verification code"
        msg["From"] = config.SMTP_FROM or config.SMTP_USER
        msg["To"] = email
        msg.set_content(f"Your verification code is: {code}")

        with smtplib.SMTP(host, port) as server:
            if config.SMTP_USE_TLS:
                server.starttls()
            if config.SMTP_USER:
                server.login(config.SMTP_USER, config.SMTP_PASS or "")
            server.send_message(msg)

    def _is_valid_email(self, email: str) -> bool:
        ascii_only = re.match(r"^[\x00-\x7F]+$", email) is not None
        pattern = re.match(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$", email)
        return bool(ascii_only and pattern)

    def _parse_time(self, value: str) -> datetime:
        return datetime.fromisoformat(value.replace("Z", ""))


user_auth = UserAuthManager()
