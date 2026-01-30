"""
Contacts Manager - Manage user's contact list
=============================================
Store and retrieve contacts for report participants.
"""

import json
import logging
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

import config

logger = logging.getLogger(__name__)

# Directory for contacts
CONTACTS_DIR = config.BASE_DIR / "contacts"
CONTACTS_DIR.mkdir(exist_ok=True)


@dataclass
class Contact:
    """A single contact."""
    id: str  # Unique ID
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    organization: Optional[str] = None  # e.g., "Israel Railways", "Contractor X"
    role: Optional[str] = None  # e.g., "Inspector", "Project Manager"
    
    def display_name(self) -> str:
        """Get display name with organization."""
        if self.organization:
            return f"{self.name} ({self.organization})"
        return self.name
    
    def short_display(self) -> str:
        """Short display for buttons."""
        if len(self.name) > 20:
            return self.name[:18] + "..."
        return self.name


class ContactsManager:
    """Manages contacts for each user."""
    
    def __init__(self):
        self._cache: dict[int, list[Contact]] = {}
    
    def _get_contacts_path(self, user_id: int) -> Path:
        """Get the contacts file path for a user."""
        return CONTACTS_DIR / f"contacts_{user_id}.json"
    
    def get_contacts(self, user_id: int) -> list[Contact]:
        """Get all contacts for a user."""
        # Check cache
        if user_id in self._cache:
            return self._cache[user_id]
        
        # Try to load from file
        contacts_path = self._get_contacts_path(user_id)
        if contacts_path.exists():
            try:
                with open(contacts_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                contacts = [Contact(**c) for c in data]
                self._cache[user_id] = contacts
                return contacts
            except Exception as e:
                logger.error(f"Failed to load contacts for user {user_id}: {e}")
        
        # Return empty list
        self._cache[user_id] = []
        return []
    
    def save_contacts(self, user_id: int, contacts: list[Contact]):
        """Save contacts to disk."""
        contacts_path = self._get_contacts_path(user_id)
        
        with open(contacts_path, "w", encoding="utf-8") as f:
            json.dump([asdict(c) for c in contacts], f, ensure_ascii=False, indent=2)
        
        self._cache[user_id] = contacts
        logger.info(f"Saved {len(contacts)} contacts for user {user_id}")
    
    def add_contact(self, user_id: int, contact: Contact) -> bool:
        """Add a new contact."""
        contacts = self.get_contacts(user_id)
        
        # Check for duplicate ID
        if any(c.id == contact.id for c in contacts):
            return False
        
        contacts.append(contact)
        self.save_contacts(user_id, contacts)
        return True
    
    def get_contact(self, user_id: int, contact_id: str) -> Optional[Contact]:
        """Get a specific contact by ID."""
        contacts = self.get_contacts(user_id)
        for c in contacts:
            if c.id == contact_id:
                return c
        return None
    
    def update_contact(self, user_id: int, contact: Contact) -> bool:
        """Update an existing contact."""
        contacts = self.get_contacts(user_id)
        
        for i, c in enumerate(contacts):
            if c.id == contact.id:
                contacts[i] = contact
                self.save_contacts(user_id, contacts)
                return True
        
        return False
    
    def delete_contact(self, user_id: int, contact_id: str) -> bool:
        """Delete a contact."""
        contacts = self.get_contacts(user_id)
        
        for i, c in enumerate(contacts):
            if c.id == contact_id:
                contacts.pop(i)
                self.save_contacts(user_id, contacts)
                return True
        
        return False
    
    def get_contacts_by_ids(self, user_id: int, contact_ids: list[str]) -> list[Contact]:
        """Get multiple contacts by their IDs."""
        contacts = self.get_contacts(user_id)
        return [c for c in contacts if c.id in contact_ids]
    
    def generate_id(self, user_id: int) -> str:
        """Generate a unique contact ID."""
        contacts = self.get_contacts(user_id)
        return f"c{len(contacts) + 1}_{user_id}"


# Singleton instance
contacts_manager = ContactsManager()
