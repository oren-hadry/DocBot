from dataclasses import asdict
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from api.auth import get_current_user
from data.contacts import contacts_manager, Contact

router = APIRouter()


class ContactCreate(BaseModel):
    name: str
    email: str
    company: Optional[str] = None
    role_title: Optional[str] = None
    phone: Optional[str] = None


@router.get("")
def list_contacts(user=Depends(get_current_user)):
    contacts = contacts_manager.get_contacts(user.user_id)
    return {"contacts": [asdict(c) for c in contacts]}


@router.post("")
def add_contact(payload: ContactCreate, user=Depends(get_current_user)):
    contact = Contact(
        id=uuid4().hex,
        name=payload.name.strip(),
        email=payload.email.strip(),
        company=payload.company,
        role_title=payload.role_title,
        phone=payload.phone,
    )
    contacts_manager.add_contact(user.user_id, contact)
    return {"status": "ok", "contact": asdict(contact)}
