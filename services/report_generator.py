"""
Report Generator - Creates professional inspection reports
==========================================================
Generates Google Docs with structured layout, branding, and photos.
"""

import json
import logging
from datetime import datetime
from typing import Optional
from openai import OpenAI
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

import config
from data.session_manager import ReportSession
from data.user_profile import UserProfile
from data.contacts_manager import Contact
from lang import _ as t

logger = logging.getLogger(__name__)


class ReportGenerator:
    """Generates structured inspection reports."""
    
    def __init__(self):
        self.openai_client = OpenAI(api_key=config.OPENAI_API_KEY)
    
    async def generate(
        self, 
        session: ReportSession, 
        google_credentials,
        user_profile: UserProfile,
        participants: list[Contact] = None
    ) -> str:
        """
        Generate a professional inspection report.
        
        Returns: URL to the created Google Doc
        """
        logger.info(f"Generating report for user {session.user_id}")
        
        # Step 1: Use GPT to structure the content
        structured_content = await self._structure_content(session)
        
        # Step 2: Create Google Doc
        doc_url = await self._create_google_doc(
            session, 
            structured_content, 
            google_credentials,
            user_profile,
            participants or []
        )
        
        return doc_url
    
    async def _structure_content(self, session: ReportSession) -> dict:
        """Use GPT to organize notes into structured findings."""
        
        all_notes = session.get_all_notes()
        num_photos = len(session.photos)
        location = session.location or "Site"
        
        prompt = f"""You are a professional report writer for field inspections.

Location: {location}
Number of photos: {num_photos}
Inspector's notes:
{all_notes}

Structure this into a professional inspection report. Output JSON:
{{
    "title": "Inspection report title",
    "summary": "Brief executive summary (2-3 sentences)",
    "findings": [
        {{
            "id": 1,
            "title": "Finding title",
            "description": "Detailed description",
            "severity": "normal|important|critical"
        }}
    ],
    "recommendations": ["recommendation 1", "recommendation 2"]
}}

Rules:
- Keep SAME LANGUAGE as the input notes (Hebrew/English/etc)
- Be concise and professional
- Create one finding per distinct issue mentioned
- If severity isn't clear, use "normal"
"""
        
        response = self.openai_client.chat.completions.create(
            model=config.GPT_MODEL,
            messages=[
                {"role": "system", "content": "You are a professional inspection report writer."},
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"},
        )
        
        structured = json.loads(response.choices[0].message.content)
        logger.info(f"Structured {len(structured.get('findings', []))} findings")
        
        return structured
    
    async def _create_google_doc(
        self, 
        session: ReportSession, 
        content: dict,
        credentials,
        profile: UserProfile,
        participants: list[Contact]
    ) -> str:
        """Create a professional Google Doc report."""
        
        docs_service = build("docs", "v1", credentials=credentials)
        drive_service = build("drive", "v3", credentials=credentials)
        
        # Create document
        location = session.location or "Site Inspection"
        date_str = datetime.now().strftime("%Y-%m-%d")
        title = content.get("title", f"Inspection Report - {location}")
        doc_title = f"{title} - {date_str}"
        
        doc = docs_service.documents().create(body={"title": doc_title}).execute()
        doc_id = doc["documentId"]
        logger.info(f"Created Google Doc: {doc_id}")
        
        # Build document content
        requests = []
        idx = 1  # Document index
        
        # ========== COMPANY HEADER ==========
        company_name = profile.get_company_display()
        if profile.company_name:
            requests.append({"insertText": {"location": {"index": idx}, "text": f"{company_name}\n"}})
            idx += len(company_name) + 1
        
        contact_info = profile.get_contact_display()
        if profile.contact_info:
            requests.append({"insertText": {"location": {"index": idx}, "text": f"{contact_info}\n"}})
            idx += len(contact_info) + 1
        
        # Separator
        sep = "━" * 60 + "\n\n"
        requests.append({"insertText": {"location": {"index": idx}, "text": sep}})
        idx += len(sep)
        
        # ========== REPORT TITLE ==========
        report_title = f"{title}\n"
        requests.append({"insertText": {"location": {"index": idx}, "text": report_title}})
        idx += len(report_title)
        
        # Date
        date_label = t("doc_date")
        date_line = f"{date_label}: {datetime.now().strftime('%d/%m/%Y')}\n"
        requests.append({"insertText": {"location": {"index": idx}, "text": date_line}})
        idx += len(date_line)
        
        # Location
        if session.location:
            loc_label = t("doc_location")
            loc_line = f"{loc_label}: {session.location}\n"
            requests.append({"insertText": {"location": {"index": idx}, "text": loc_line}})
            idx += len(loc_line)
        
        requests.append({"insertText": {"location": {"index": idx}, "text": "\n"}})
        idx += 1
        
        # ========== PARTICIPANTS ==========
        if participants:
            part_label = t("doc_participants")
            part_header = f"{part_label}:\n"
            requests.append({"insertText": {"location": {"index": idx}, "text": part_header}})
            idx += len(part_header)
            
            for p in participants:
                p_line = f"• {p.name}"
                if p.organization:
                    p_line += f" ({p.organization})"
                if p.email:
                    p_line += f" - {p.email}"
                p_line += "\n"
                requests.append({"insertText": {"location": {"index": idx}, "text": p_line}})
                idx += len(p_line)
            
            requests.append({"insertText": {"location": {"index": idx}, "text": "\n"}})
            idx += 1
        
        # ========== SUMMARY ==========
        summary = content.get("summary", "")
        if summary:
            sum_label = t("doc_summary")
            sum_header = f"{sum_label}:\n"
            requests.append({"insertText": {"location": {"index": idx}, "text": sum_header}})
            idx += len(sum_header)
            
            sum_text = f"{summary}\n\n"
            requests.append({"insertText": {"location": {"index": idx}, "text": sum_text}})
            idx += len(sum_text)
        
        # ========== FINDINGS ==========
        findings = content.get("findings", [])
        if findings:
            find_label = t("doc_findings")
            find_header = f"{find_label}:\n\n"
            requests.append({"insertText": {"location": {"index": idx}, "text": find_header}})
            idx += len(find_header)
            
            for i, finding in enumerate(findings, 1):
                severity = finding.get("severity", "normal")
                severity_emoji = {"critical": "🔴", "important": "🟡", "normal": "🟢"}.get(severity, "⚪")
                
                f_title = finding.get("title", f"{t('doc_finding')} {i}")
                f_header = f"{severity_emoji} {i}. {f_title}\n"
                requests.append({"insertText": {"location": {"index": idx}, "text": f_header}})
                idx += len(f_header)
                
                f_desc = finding.get("description", "")
                if f_desc:
                    f_text = f"   {f_desc}\n\n"
                    requests.append({"insertText": {"location": {"index": idx}, "text": f_text}})
                    idx += len(f_text)
        
        # ========== RECOMMENDATIONS ==========
        recommendations = content.get("recommendations", [])
        if recommendations:
            rec_label = t("doc_recommendations")
            rec_header = f"{rec_label}:\n"
            requests.append({"insertText": {"location": {"index": idx}, "text": rec_header}})
            idx += len(rec_header)
            
            for rec in recommendations:
                rec_line = f"• {rec}\n"
                requests.append({"insertText": {"location": {"index": idx}, "text": rec_line}})
                idx += len(rec_line)
            
            requests.append({"insertText": {"location": {"index": idx}, "text": "\n"}})
            idx += 1
        
        # ========== PHOTOS SECTION ==========
        if session.photos:
            photos_label = t("doc_photos")
            photos_header = f"{photos_label}:\n\n"
            requests.append({"insertText": {"location": {"index": idx}, "text": photos_header}})
            idx += len(photos_header)
        
        # Execute text insertions
        if requests:
            docs_service.documents().batchUpdate(
                documentId=doc_id,
                body={"requests": requests}
            ).execute()
        
        # ========== INSERT LOGO ==========
        if profile.logo_path:
            await self._insert_image_at_start(
                profile.logo_path,
                doc_id,
                docs_service,
                drive_service,
                width=100,
                height=50
            )
        
        # ========== INSERT PHOTOS ==========
        if session.photos:
            await self._insert_photos(
                session.photos, 
                doc_id, 
                docs_service, 
                drive_service
            )
        
        # ========== ADD PAGE NUMBERS ==========
        await self._add_page_numbers(doc_id, docs_service)
        
        doc_url = f"https://docs.google.com/document/d/{doc_id}/edit"
        logger.info(f"Report complete: {doc_url}")
        
        return doc_url
    
    async def _insert_image_at_start(
        self,
        image_path: str,
        doc_id: str,
        docs_service,
        drive_service,
        width: int = 100,
        height: int = 50
    ):
        """Insert an image at the beginning of the document."""
        try:
            file_metadata = {"name": "logo.png"}
            media = MediaFileUpload(image_path, mimetype="image/png")
            
            uploaded = drive_service.files().create(
                body=file_metadata,
                media_body=media,
                fields="id"
            ).execute()
            
            drive_service.permissions().create(
                fileId=uploaded["id"],
                body={"type": "anyone", "role": "reader"}
            ).execute()
            
            file_info = drive_service.files().get(
                fileId=uploaded["id"],
                fields="webContentLink"
            ).execute()
            
            image_url = file_info.get("webContentLink", "").replace("&export=download", "")
            
            if image_url:
                docs_service.documents().batchUpdate(
                    documentId=doc_id,
                    body={
                        "requests": [
                            {
                                "insertInlineImage": {
                                    "location": {"index": 1},
                                    "uri": image_url,
                                    "objectSize": {
                                        "height": {"magnitude": height, "unit": "PT"},
                                        "width": {"magnitude": width, "unit": "PT"}
                                    }
                                }
                            },
                            {
                                "insertText": {
                                    "location": {"index": 2},
                                    "text": "\n"
                                }
                            }
                        ]
                    }
                ).execute()
                
            logger.info("Logo inserted")
            
        except Exception as e:
            logger.error(f"Failed to insert logo: {e}")
    
    async def _insert_photos(
        self, 
        photo_paths: list, 
        doc_id: str,
        docs_service,
        drive_service
    ):
        """Upload and insert photos at the end of document."""
        photo_label = t("doc_photo")
        
        for i, photo_path in enumerate(photo_paths):
            try:
                file_metadata = {"name": f"photo_{i+1}.jpg"}
                media = MediaFileUpload(photo_path, mimetype="image/jpeg")
                
                uploaded = drive_service.files().create(
                    body=file_metadata,
                    media_body=media,
                    fields="id"
                ).execute()
                
                drive_service.permissions().create(
                    fileId=uploaded["id"],
                    body={"type": "anyone", "role": "reader"}
                ).execute()
                
                file_info = drive_service.files().get(
                    fileId=uploaded["id"],
                    fields="webContentLink"
                ).execute()
                
                image_url = file_info.get("webContentLink", "").replace("&export=download", "")
                
                if image_url:
                    doc = docs_service.documents().get(documentId=doc_id).execute()
                    end_idx = doc["body"]["content"][-1]["endIndex"] - 1
                    
                    label = f"{photo_label} {i+1}:\n"
                    docs_service.documents().batchUpdate(
                        documentId=doc_id,
                        body={"requests": [{"insertText": {"location": {"index": end_idx}, "text": label}}]}
                    ).execute()
                    
                    doc = docs_service.documents().get(documentId=doc_id).execute()
                    end_idx = doc["body"]["content"][-1]["endIndex"] - 1
                    
                    docs_service.documents().batchUpdate(
                        documentId=doc_id,
                        body={
                            "requests": [{
                                "insertInlineImage": {
                                    "location": {"index": end_idx},
                                    "uri": image_url,
                                    "objectSize": {
                                        "height": {"magnitude": 200, "unit": "PT"},
                                        "width": {"magnitude": 300, "unit": "PT"}
                                    }
                                }
                            }]
                        }
                    ).execute()
                    
                    doc = docs_service.documents().get(documentId=doc_id).execute()
                    end_idx = doc["body"]["content"][-1]["endIndex"] - 1
                    docs_service.documents().batchUpdate(
                        documentId=doc_id,
                        body={"requests": [{"insertText": {"location": {"index": end_idx}, "text": "\n\n"}}]}
                    ).execute()
                    
                logger.info(f"Inserted photo {i+1}")
                
            except Exception as e:
                logger.error(f"Failed to insert photo {i+1}: {e}")
    
    async def _add_page_numbers(self, doc_id: str, docs_service):
        """Add page numbers to footer."""
        page_label = t("doc_page")
        
        try:
            docs_service.documents().batchUpdate(
                documentId=doc_id,
                body={
                    "requests": [
                        {
                            "createFooter": {
                                "type": "DEFAULT"
                            }
                        }
                    ]
                }
            ).execute()
            
            doc = docs_service.documents().get(documentId=doc_id).execute()
            footer_id = None
            
            footers = doc.get("footers", {})
            if footers:
                footer_id = list(footers.keys())[0]
            
            if footer_id:
                footer_content = doc.get("footers", {}).get(footer_id, {})
                footer_idx = footer_content.get("content", [{}])[0].get("startIndex", 1)
                
                docs_service.documents().batchUpdate(
                    documentId=doc_id,
                    body={
                        "requests": [
                            {
                                "insertText": {
                                    "location": {"segmentId": footer_id, "index": footer_idx},
                                    "text": f"{page_label} "
                                }
                            }
                        ]
                    }
                ).execute()
            
            logger.info("Added page numbers")
            
        except Exception as e:
            logger.warning(f"Could not add page numbers: {e}")


# Singleton instance
report_generator = ReportGenerator()
