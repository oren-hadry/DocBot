import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional
from uuid import uuid4

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
    template_key: str = "INSPECTION_REPORT"
    attendees: list[str] = field(default_factory=list)
    distribution_list: list[str] = field(default_factory=list)
    items: list[ReportItem] = field(default_factory=list)
    photos: list[ReportPhoto] = field(default_factory=list)

    def next_number(self) -> str:
        return str(len(self.items) + 1)


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
        )
        self._sessions[user_id] = session
        return session

    def get_session(self, user_id: int) -> Optional[ReportSession]:
        return self._sessions.get(user_id)

    def add_item(self, user_id: int, description: str, notes: str = "") -> ReportItem:
        session = self._sessions[user_id]
        item = ReportItem(
            id=uuid4().hex,
            number=session.next_number(),
            description=description,
            notes=notes,
        )
        session.items.append(item)
        return item

    def add_photo(self, user_id: int, file_path: str, item_id: Optional[str]) -> ReportPhoto:
        session = self._sessions[user_id]
        photo = ReportPhoto(
            id=uuid4().hex,
            file_path=file_path,
            item_id=item_id,
        )
        session.photos.append(photo)
        return photo

    def set_contacts(self, user_id: int, attendees: list[str], distribution_list: list[str]) -> None:
        session = self._sessions[user_id]
        session.attendees = attendees
        session.distribution_list = distribution_list

    def finalize(self, user_id: int) -> ReportSession:
        session = self._sessions.pop(user_id)
        return session


report_manager = ReportManager()
