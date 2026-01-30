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
    def get_contacts(self, user_id: int) -> list[Contact]:
        path = user_contacts_file(user_id)
        if not path.exists():
            return []
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return [Contact(**c) for c in data]

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
