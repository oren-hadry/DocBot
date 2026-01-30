import os
from pathlib import Path
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from starlette.responses import FileResponse

from api.auth import get_current_user
from data.templates import TEMPLATES
from data.report_manager import report_manager
from data.stats import stats_manager
from data.storage import user_temp_dir
from data.word_generator import generate_report_docx

router = APIRouter()


class StartReportRequest(BaseModel):
    location: Optional[str] = None
    template_key: Optional[str] = None


class AddItemRequest(BaseModel):
    description: str
    notes: Optional[str] = ""


class SetContactsRequest(BaseModel):
    attendees: list[str] = []
    distribution_list: list[str] = []


@router.post("/start")
def start_report(payload: StartReportRequest, user=Depends(get_current_user)):
    report_manager.create_session(
        user.user_id,
        location=payload.location or "",
        template_key=payload.template_key or "",
    )
    stats_manager.increment(user.user_id, "reports_started")
    return {"status": "ok"}


@router.get("/templates")
def list_templates(user=Depends(get_current_user)):
    return {"templates": [{"key": t.key, "title": t.title} for t in TEMPLATES]}


@router.post("/contacts")
def set_contacts(payload: SetContactsRequest, user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")
    report_manager.set_contacts(user.user_id, payload.attendees, payload.distribution_list)
    return {"status": "ok"}


@router.post("/item")
def add_item(payload: AddItemRequest, user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")
    description = payload.description.strip()
    if not description:
        raise HTTPException(status_code=400, detail="Description required")
    item = report_manager.add_item(user.user_id, description=description, notes=payload.notes or "")
    stats_manager.increment(user.user_id, "items_added")
    return {"status": "ok", "item_id": item.id, "number": item.number}


@router.post("/photo")
async def add_photo(
    item_id: Optional[str] = None,
    file: UploadFile = File(...),
    user=Depends(get_current_user),
):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")

    suffix = Path(file.filename or "photo.jpg").suffix or ".jpg"
    photo_path = user_temp_dir(user.user_id) / f"photo_{uuid4().hex}{suffix}"
    content = await file.read()
    with open(photo_path, "wb") as f:
        f.write(content)

    report_manager.add_photo(user.user_id, str(photo_path), item_id=item_id)
    stats_manager.increment(user.user_id, "photos_added")
    return {"status": "ok"}


@router.post("/finalize")
def finalize_report(background_tasks: BackgroundTasks, user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session or not session.items:
        raise HTTPException(status_code=400, detail="No items to generate report")

    session = report_manager.finalize(user.user_id)
    doc_path = generate_report_docx(session)
    stats_manager.increment(user.user_id, "reports_created")

    filename = os.path.basename(doc_path)
    return FileResponse(
        path=doc_path,
        filename=filename,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    )
