import os
from pathlib import Path
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
import logging
from pydantic import BaseModel
from starlette.responses import FileResponse

from api.auth import get_current_user
from data.templates import TEMPLATES
from data.report_manager import report_manager
from data.locations import locations_manager
from data.report_store import report_store
from data.audit_log import log_event
from data.stats import stats_manager
from data.storage import user_temp_dir
from data.word_generator import generate_report_docx
from data.voice_transcriber import transcribe_audio

router = APIRouter()
logger = logging.getLogger("docbot.report")


class StartReportRequest(BaseModel):
    location: Optional[str] = None
    template_key: Optional[str] = None
    project_name: Optional[str] = None


class AddItemRequest(BaseModel):
    description: str
    notes: Optional[str] = ""
    allow_empty: Optional[bool] = False


class SetContactsRequest(BaseModel):
    attendees: list[str] = []
    distribution_list: list[str] = []


class UpdateItemRequest(BaseModel):
    description: str
    notes: Optional[str] = ""


class OrganizeRequest(BaseModel):
    folder: str = ""
    tags: list[str] = []


@router.post("/start")
def start_report(payload: StartReportRequest, user=Depends(get_current_user)):
    session = report_manager.create_session(
        user.user_id,
        location=payload.location or "",
        template_key=payload.template_key or "",
        project_name=payload.project_name or "",
    )
    if payload.location:
        locations_manager.add_location(user.user_id, payload.location)
    stats_manager.increment(user.user_id, "reports_started")
    log_event(
        user.user_id,
        "START_REPORT",
        {
            "location": session.location,
            "template_key": session.template_key,
            "project_name": session.project_name,
        },
    )
    return {"status": "ok"}


@router.get("/templates")
def list_templates(user=Depends(get_current_user)):
    return {"templates": [{"key": t.key, "title": t.title, "title_he": t.title_he} for t in TEMPLATES]}


@router.get("/recent")
def list_recent_reports(user=Depends(get_current_user)):
    reports = report_store.list_reports(user.user_id)
    return {
        "reports": [
            {
                "report_id": r.report_id,
                "created_at": r.created_at,
                "location": r.location,
                "template_key": r.template_key,
                "title": r.title,
                "folder": r.folder,
                "tags": r.tags or [],
            }
            for r in reports
        ]
    }


@router.get("/session")
def get_active_session(user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")
    return {"session": session.to_dict()}


@router.get("/locations")
def list_locations(user=Depends(get_current_user)):
    return {"locations": locations_manager.get_locations(user.user_id)}


@router.get("/photo/{photo_id}")
def get_photo(photo_id: str, user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")
    photo = next((p for p in session.photos if p.id == photo_id), None)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    if not Path(photo.file_path).exists():
        raise HTTPException(status_code=404, detail="Photo file missing")
    return FileResponse(path=photo.file_path)


@router.post("/contacts")
def set_contacts(payload: SetContactsRequest, user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")
    try:
        report_manager.set_contacts(user.user_id, payload.attendees, payload.distribution_list)
    except ValueError:
        raise HTTPException(status_code=400, detail="No active report")
    log_event(
        user.user_id,
        "SET_CONTACTS",
        {"attendees": payload.attendees, "distribution_list": payload.distribution_list},
    )
    return {"status": "ok"}


@router.post("/item")
def add_item(payload: AddItemRequest, user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")
    description = payload.description.strip()
    notes = (payload.notes or "").strip()
    if not description and not notes and not payload.allow_empty:
        raise HTTPException(status_code=400, detail="Description or notes required")
    item = report_manager.add_item(user.user_id, description=description, notes=notes)
    stats_manager.increment(user.user_id, "items_added")
    log_event(
        user.user_id,
        "ADD_ITEM",
        {"item_id": item.id, "number": item.number},
    )
    return {"status": "ok", "item_id": item.id, "number": item.number}


@router.put("/item/{item_id}")
def update_item(item_id: str, payload: UpdateItemRequest, user=Depends(get_current_user)):
    try:
        report_manager.update_item(user.user_id, item_id, payload.description.strip(), payload.notes or "")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    log_event(user.user_id, "UPDATE_ITEM", {"item_id": item_id})
    return {"status": "ok"}


@router.post("/photo")
async def add_photo(
    item_id: Optional[str] = Form(None),
    file: UploadFile = File(...),
    user=Depends(get_current_user),
):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")

    item_id = item_id.strip() if item_id else None
    if item_id and not any(item.id == item_id for item in session.items):
        logger.warning("Photo item_id not found: user_id=%s item_id=%s", user.user_id, item_id)
        item_id = None

    suffix = Path(file.filename or "photo.jpg").suffix or ".jpg"
    photo_path = user_temp_dir(user.user_id) / f"photo_{uuid4().hex}{suffix}"
    content = await file.read()
    with open(photo_path, "wb") as f:
        f.write(content)

    report_manager.add_photo(user.user_id, str(photo_path), item_id=item_id)
    stats_manager.increment(user.user_id, "photos_added")
    logger.info(
        "Photo saved: user_id=%s item_id=%s path=%s bytes=%s",
        user.user_id,
        item_id or "-",
        photo_path.name,
        len(content),
    )
    log_event(
        user.user_id,
        "ADD_PHOTO",
        {"item_id": item_id, "photo": photo_path.name},
    )
    return {"status": "ok"}


@router.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: Optional[str] = Form(None),
    user=Depends(get_current_user),
):
    if language:
        language = language.lower()
        if language == "iw":
            language = "he"
    suffix = Path(file.filename or "audio.m4a").suffix or ".m4a"
    audio_path = user_temp_dir(user.user_id) / f"audio_{uuid4().hex}{suffix}"
    content = await file.read()
    with open(audio_path, "wb") as f:
        f.write(content)
    try:
        text = transcribe_audio(str(audio_path), language=language)
    finally:
        try:
            audio_path.unlink()
        except Exception:
            pass
    log_event(
        user.user_id,
        "TRANSCRIBE_AUDIO",
        {"language": language or "", "bytes": len(content)},
    )
    return {"text": text}


@router.post("/finalize")
async def finalize_report(
    background_tasks: BackgroundTasks,
    logo: Optional[UploadFile] = File(None),
    user=Depends(get_current_user),
):
    session = report_manager.get_session(user.user_id)
    if not session:
        logger.warning("Finalize failed: no active report for user_id=%s", user.user_id)
        raise HTTPException(status_code=400, detail="No active report")
    if not session.items:
        logger.info("Finalize with empty report: user_id=%s", user.user_id)

    logo_path = None
    if logo:
        suffix = Path(logo.filename or "logo.png").suffix or ".png"
        logo_path = user_temp_dir(user.user_id) / f"logo_{uuid4().hex}{suffix}"
        content = await logo.read()
        with open(logo_path, "wb") as f:
            f.write(content)

    session = report_manager.finalize(user.user_id)
    
    # Use profile logo if no logo provided in request
    final_logo_path = str(logo_path) if logo_path else user.logo_path
    
    doc_path = generate_report_docx(session, logo_path=final_logo_path)

    if logo_path:
        try:
            logo_path.unlink()
        except Exception:
            pass

    report_store.save_report(user.user_id, session, doc_path)
    stats_manager.increment(user.user_id, "reports_created")

    filename = os.path.basename(doc_path)
    log_event(user.user_id, "FINALIZE_REPORT", {"doc": filename})
    return FileResponse(
        path=doc_path,
        filename=filename,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    )


@router.post("/finalize_pdf")
async def finalize_report_pdf(
    background_tasks: BackgroundTasks,
    logo: Optional[UploadFile] = File(None),
    user=Depends(get_current_user),
):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")

    logo_path = None
    if logo:
        suffix = Path(logo.filename or "logo.png").suffix or ".png"
        logo_path = user_temp_dir(user.user_id) / f"logo_{uuid4().hex}{suffix}"
        content = await logo.read()
        with open(logo_path, "wb") as f:
            f.write(content)

    session = report_manager.finalize(user.user_id)
    # Use profile logo if no logo provided in request
    final_logo_path = str(logo_path) if logo_path else user.logo_path

    # For now, we still generate DOCX and then we would ideally convert to PDF.
    # Since direct DOCX->PDF is hard without external tools, 
    # I will implement a basic PDF generator using fpdf2 for Hebrew support.
    from data.pdf_generator import generate_report_pdf
    pdf_path = generate_report_pdf(session, logo_path=final_logo_path)

    if logo_path:
        try:
            logo_path.unlink()
        except Exception:
            pass

    report_store.save_report(user.user_id, session, pdf_path)
    stats_manager.increment(user.user_id, "reports_created")

    filename = os.path.basename(pdf_path)
    log_event(user.user_id, "FINALIZE_REPORT_PDF", {"doc": filename})
    return FileResponse(
        path=pdf_path,
        filename=filename,
        media_type="application/pdf",
    )


@router.post("/cancel")
def cancel_report(user=Depends(get_current_user)):
    session = report_manager.get_session(user.user_id)
    if not session:
        raise HTTPException(status_code=400, detail="No active report")
    report_manager.finalize(user.user_id)
    log_event(user.user_id, "CANCEL_REPORT", {})
    return {"status": "ok"}


@router.post("/{report_id}/open")
def open_report(report_id: str, user=Depends(get_current_user)):
    data = report_store.get_report_data(user.user_id, report_id)
    if not data:
        raise HTTPException(status_code=404, detail="Report not found")
    report_manager.load_from_report(user.user_id, data)
    log_event(user.user_id, "OPEN_REPORT", {"report_id": report_id})
    return {"status": "ok"}


@router.post("/{report_id}/organize")
def organize_report(report_id: str, payload: OrganizeRequest, user=Depends(get_current_user)):
    result = report_store.update_organize(user.user_id, report_id, payload.folder, payload.tags)
    if not result:
        raise HTTPException(status_code=404, detail="Report not found")
    log_event(
        user.user_id,
        "ORGANIZE_REPORT",
        {"report_id": report_id, "folder": payload.folder, "tags": payload.tags},
    )
    return {"status": "ok"}
