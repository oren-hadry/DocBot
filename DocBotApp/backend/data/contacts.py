import json
from dataclasses import dataclass, asdict
from typing import Optional

from data.storage import user_contacts_file


@dataclass
class Contact:
    id: str
    name: str
    email: str
    company: Optional[str] = None
    role_title: Optional[str] = None
    phone: Optional[str] = None


class ContactsManager:
    def _recover_from_text(self, text: str) -> list[Contact] | None:
        if not text:
            return None
        start = text.find("[")
        end = text.rfind("]")
        if start != -1 and end != -1 and end > start:
            try:
                data = json.loads(text[start : end + 1])
                return [Contact(**c) for c in data if isinstance(c, dict)]
            except Exception:
                return None
        return None

    def get_contacts(self, user_id: int) -> list[Contact]:
        path = user_contacts_file(user_id)
        if not path.exists():
            return []
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
            data = json.loads(content)
            return [Contact(**c) for c in data]
        except Exception:
            recovered = self._recover_from_text(content if "content" in locals() else "")
            if recovered is not None:
                self.save_contacts(user_id, recovered)
                return recovered
            try:
                path.unlink(missing_ok=True)
            except Exception:
                pass
            return []

    def save_contacts(self, user_id: int, contacts: list[Contact]) -> None:
        path = user_contacts_file(user_id)
        with open(path, "w", encoding="utf-8") as f:
            json.dump([asdict(c) for c in contacts], f, ensure_ascii=False, indent=2)

    def add_contact(self, user_id: int, contact: Contact) -> None:
        contacts = self.get_contacts(user_id)
        contacts.append(contact)
        self.save_contacts(user_id, contacts)

    def get_contacts_by_ids(self, user_id: int, ids: list[str]) -> list[Contact]:
        contacts = self.get_contacts(user_id)
        return [c for c in contacts if c.id in ids]


contacts_manager = ContactsManager()
