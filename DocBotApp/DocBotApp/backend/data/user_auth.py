import json
import logging
from dataclasses import dataclass, asdict
from datetime import datetime
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
    password_hash: str
    created_at: str


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
                self._cache = {u["phone"]: UserRecord(**u) for u in data}
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

    def create_user(self, phone: str, password: str) -> UserRecord:
        users = self._load_all()
        if phone in users:
            raise ValueError("User already exists")
        password_hash = pwd_context.hash(password)
        user = UserRecord(
            user_id=self._next_user_id(users),
            phone=phone,
            password_hash=password_hash,
            created_at=datetime.utcnow().isoformat(timespec="seconds") + "Z",
        )
        users[phone] = user
        self._save_all(users)
        return user

    def verify_password(self, user: UserRecord, password: str) -> bool:
        return pwd_context.verify(password, user.password_hash)


user_auth = UserAuthManager()
