import json
import shutil
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Optional
from uuid import uuid4

from data.report_manager import ReportSession, ReportPhoto
from data.storage import user_reports_index_file, user_report_data_dir


@dataclass
class ReportSummary:
    report_id: str
    created_at: str
    location: str
    template_key: str
    title: str
    title_he: str = ""
    folder: str = ""
    project_name: str = ""
    tags: list[str] = None

    def to_dict(self) -> dict:
        data = asdict(self)
        data["tags"] = self.tags or []
        return data


class ReportStore:
    def list_reports(self, user_id: int) -> list[ReportSummary]:
        path = user_reports_index_file(user_id)
        if not path.exists():
            return []
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return [ReportSummary(**item) for item in data]

    def save_report(self, user_id: int, session: ReportSession, docx_path: str) -> ReportSummary:
        report_id = uuid4().hex
        created_at = datetime.utcnow().isoformat(timespec="seconds") + "Z"
        report_dir = user_report_data_dir(user_id, report_id)

        # Copy docx
        docx_dest = report_dir / Path(docx_path).name
        shutil.copy2(docx_path, docx_dest)

        # Copy photos and update paths
        updated_photos: list[ReportPhoto] = []
        photos_dir = report_dir / "photos"
        photos_dir.mkdir(parents=True, exist_ok=True)
        for photo in session.photos:
            src = Path(photo.file_path)
            if src.exists():
                dest = photos_dir / src.name
                shutil.copy2(src, dest)
                updated_photos.append(ReportPhoto(id=photo.id, file_path=str(dest), item_id=photo.item_id, caption=photo.caption))
            else:
                updated_photos.append(photo)

        session.photos = updated_photos

        # Save report data
        with open(report_dir / "report.json", "w", encoding="utf-8") as f:
            json.dump(session.to_dict(), f, ensure_ascii=False, indent=2)

        summary = ReportSummary(
            report_id=report_id,
            created_at=created_at,
            location=session.location,
            template_key=session.template_key,
            title=session.title,
            title_he=session.title_he,
            folder="",
            project_name=session.project_name,
            tags=[],
        )
        self._append_summary(user_id, summary)
        return summary

    def get_report_data(self, user_id: int, report_id: str) -> Optional[dict]:
        report_dir = user_report_data_dir(user_id, report_id)
        report_path = report_dir / "report.json"
        if not report_path.exists():
            return None
        with open(report_path, "r", encoding="utf-8") as f:
            return json.load(f)

    def update_organize(self, user_id: int, report_id: str, folder: str, tags: list[str]) -> Optional[ReportSummary]:
        summaries = self.list_reports(user_id)
        updated = []
        result = None
        for summary in summaries:
            if summary.report_id == report_id:
                summary.folder = folder
                summary.tags = tags
                result = summary
            updated.append(summary)
        if result:
            self._save_index(user_id, updated)
        return result

    def delete_report(self, user_id: int, report_id: str) -> bool:
        """Delete a report and its associated files."""
        # Remove from index
        summaries = self.list_reports(user_id)
        original_len = len(summaries)
        summaries = [s for s in summaries if s.report_id != report_id]
        if len(summaries) == original_len:
            return False  # Report not found
        self._save_index(user_id, summaries)
        
        # Delete report directory
        report_dir = user_report_data_dir(user_id, report_id)
        if report_dir.exists():
            shutil.rmtree(report_dir)
        
        return True

    def _append_summary(self, user_id: int, summary: ReportSummary) -> None:
        summaries = self.list_reports(user_id)
        summaries.insert(0, summary)
        self._save_index(user_id, summaries)

    def _save_index(self, user_id: int, summaries: list[ReportSummary]) -> None:
        path = user_reports_index_file(user_id)
        with open(path, "w", encoding="utf-8") as f:
            json.dump([s.to_dict() for s in summaries], f, ensure_ascii=False, indent=2)


report_store = ReportStore()
