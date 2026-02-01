import json
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Optional
from uuid import uuid4

from data.storage import user_session_file
from data.templates import get_template


@dataclass
class ReportItem:
    id: str
    number: str
    description: str
    notes: str = ""


@dataclass
class ReportPhoto:
    id: str
    file_path: str
    item_id: Optional[str] = None
    caption: Optional[str] = None


@dataclass
class ReportSession:
    user_id: int
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat(timespec="seconds") + "Z")
    location: str = ""
    title: str = "Inspection Report"
    title_he: str = "דוח פיקוח"
    template_key: str = "INSPECTION_REPORT"
    attendees: list[str] = field(default_factory=list)
    distribution_list: list[str] = field(default_factory=list)
    items: list[ReportItem] = field(default_factory=list)
    photos: list[ReportPhoto] = field(default_factory=list)

    def next_number(self) -> str:
        return str(len(self.items) + 1)

    def to_dict(self) -> dict:
        return {
            "user_id": self.user_id,
            "created_at": self.created_at,
            "location": self.location,
            "title": self.title,
            "title_he": self.title_he,
            "template_key": self.template_key,
            "attendees": self.attendees,
            "distribution_list": self.distribution_list,
            "items": [asdict(i) for i in self.items],
            "photos": [asdict(p) for p in self.photos],
        }

    @classmethod
    def from_dict(cls, data: dict) -> "ReportSession":
        session = cls(
            user_id=data["user_id"],
            created_at=data.get("created_at", datetime.utcnow().isoformat(timespec="seconds") + "Z"),
            location=data.get("location", ""),
            title=data.get("title", "Inspection Report"),
            title_he=data.get("title_he", "דוח פיקוח"),
            template_key=data.get("template_key", "INSPECTION_REPORT"),
            attendees=data.get("attendees", []),
            distribution_list=data.get("distribution_list", []),
        )
        session.items = [ReportItem(**i) for i in data.get("items", [])]
        session.photos = [ReportPhoto(**p) for p in data.get("photos", [])]
        return session


class ReportManager:
    def __init__(self):
        self._sessions: dict[int, ReportSession] = {}

    def create_session(self, user_id: int, location: str = "", template_key: str = "") -> ReportSession:
        template = get_template(template_key) if template_key else get_template("INSPECTION_REPORT")
        session = ReportSession(
            user_id=user_id,
            location=location.strip(),
            template_key=template.key,
            title=template.title,
            title_he=template.title_he,
        )
        self._sessions[user_id] = session
        self._save_session(session)
        return session

    def get_session(self, user_id: int) -> Optional[ReportSession]:
        session = self._sessions.get(user_id)
        if session:
            return session
        path = user_session_file(user_id)
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            session = ReportSession.from_dict(data)
            self._sessions[user_id] = session
            return session
        return None

    def add_item(self, user_id: int, description: str, notes: str = "") -> ReportItem:
        session = self._sessions[user_id]
        item = ReportItem(
            id=uuid4().hex,
            number=session.next_number(),
            description=description,
            notes=notes,
        )
        session.items.append(item)
        self._save_session(session)
        return item

    def add_photo(self, user_id: int, file_path: str, item_id: Optional[str]) -> ReportPhoto:
        session = self._sessions[user_id]
        photo = ReportPhoto(
            id=uuid4().hex,
            file_path=file_path,
            item_id=item_id,
        )
        session.photos.append(photo)
        self._save_session(session)
        return photo

    def set_contacts(self, user_id: int, attendees: list[str], distribution_list: list[str]) -> None:
        session = self.get_session(user_id)
        if not session:
            raise ValueError("No active report")
        session.attendees = attendees
        session.distribution_list = distribution_list
        self._save_session(session)

    def update_item(self, user_id: int, item_id: str, description: str, notes: str) -> None:
        session = self.get_session(user_id)
        if not session:
            raise ValueError("No active report")
        for item in session.items:
            if item.id == item_id:
                item.description = description
                item.notes = notes
                self._save_session(session)
                return
        raise ValueError("Item not found")

    def load_from_report(self, session_data: dict) -> ReportSession:
        session = ReportSession.from_dict(session_data)
        self._sessions[session.user_id] = session
        self._save_session(session)
        return session

    def _save_session(self, session: ReportSession) -> None:
        path = user_session_file(session.user_id)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(session.to_dict(), f, ensure_ascii=False, indent=2)

    def finalize(self, user_id: int) -> ReportSession:
        session = self._sessions.pop(user_id)
        path = user_session_file(user_id)
        if path.exists():
            path.unlink()
        return session


report_manager = ReportManager()
