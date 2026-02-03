import os
from datetime import datetime
from pathlib import Path
from fpdf import FPDF
from data.report_manager import ReportSession
from data.user_auth import user_auth
from data.storage import user_reports_dir


def _find_unicode_font():
    """Find a Unicode TTF font that supports Hebrew on the system."""
    font_paths = [
        # macOS
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Unicode.ttf",
        "/Library/Fonts/Arial.ttf",
        # Linux
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        # Common locations
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
    ]
    for path in font_paths:
        if os.path.exists(path):
            return path
    return None


class DocBotPDF(FPDF):
    def __init__(self, has_hebrew=False):
        super().__init__()
        self.has_hebrew = has_hebrew
        self._font_name = "helvetica"  # fallback
        
        # Add Unicode font for Hebrew support
        font_path = _find_unicode_font()
        if font_path:
            try:
                self.add_font("UniFont", "", font_path)
                self.add_font("UniFont", "B", font_path)  # Use same for bold
                self._font_name = "UniFont"
            except Exception:
                pass  # Fall back to helvetica

    def set_doc_font(self, style="", size=12):
        """Set font with fallback."""
        try:
            self.set_font(self._font_name, style, size)
        except Exception:
            self.set_font("helvetica", style, size)

    def header(self):
        pass

    def footer(self):
        self.set_y(-15)
        self.set_doc_font("I", 8)
        self.cell(0, 10, f"Page {self.page_no()}", 0, 0, "C")


def generate_report_pdf(session: ReportSession, logo_path: str = None) -> str:
    has_hebrew = any(ch >= "\u0590" and ch <= "\u05FF" for ch in (session.location + session.title))
    
    pdf = DocBotPDF(has_hebrew=has_hebrew)
    pdf.add_page()
    
    align = "R" if has_hebrew else "L"
    
    if logo_path and os.path.exists(logo_path):
        try:
            pdf.image(logo_path, x=80, w=50)
            pdf.ln(10)
        except Exception:
            pass

    pdf.set_doc_font("B", 16)
    pdf.cell(0, 10, session.title, ln=True, align="C")
    pdf.set_doc_font("", 12)
    pdf.ln(5)
    
    pdf.set_doc_font("B", 12)
    date_label = "תאריך" if has_hebrew else "Date"
    pdf.cell(0, 10, f"{date_label}: {datetime.now().strftime('%d/%m/%Y')}", ln=True, align=align)
    
    if session.location:
        loc_label = "מיקום" if has_hebrew else "Location"
        pdf.cell(0, 10, f"{loc_label}: {session.location}", ln=True, align=align)
    if session.project_name:
        proj_label = "פרויקט" if has_hebrew else "Project"
        pdf.cell(0, 10, f"{proj_label}: {session.project_name}", ln=True, align=align)
    
    pdf.ln(10)
    pdf.set_doc_font("B", 14)
    findings_label = "ממצאים" if has_hebrew else "Findings"
    pdf.cell(0, 10, findings_label, ln=True, align=align)
    pdf.set_doc_font("", 11)
    
    for item in session.items:
        pdf.set_doc_font("B", 11)
        item_label = "סעיף" if has_hebrew else "Item"
        pdf.cell(0, 10, f"{item_label} {item.number}: {item.description}", ln=True, align=align)
        pdf.set_doc_font("", 11)
        if item.notes:
            notes_label = "הערות" if has_hebrew else "Notes"
            pdf.multi_cell(0, 10, f"{notes_label}: {item.notes}", align=align)
        
        photos = [p for p in session.photos if p.item_id == item.id]
        if photos:
            for p in photos:
                if os.path.exists(p.file_path):
                    try:
                        pdf.image(p.file_path, w=100)
                        pdf.ln(5)
                    except Exception:
                        pass
        pdf.ln(5)

    # Signature
    user = user_auth.get_by_id(session.user_id)
    if user and user.full_name:
        pdf.ln(10)
        
        if user.signature_path and os.path.exists(user.signature_path):
            try:
                pdf.image(user.signature_path, w=40)
                pdf.ln(5)
            except Exception:
                pass
            
        pdf.line(10, pdf.get_y(), 200, pdf.get_y())
        pdf.ln(5)
        pdf.set_doc_font("B", 11)
        written_label = "נכתב על ידי" if has_hebrew else "Written by"
        pdf.cell(0, 10, f"{written_label}: {user.full_name}", ln=True)
        pdf.set_doc_font("", 11)
        if user.role_title:
            pdf.cell(0, 10, user.role_title, ln=True)
        contact = []
        if user.company_name: contact.append(user.company_name)
        if user.phone_contact: contact.append(user.phone_contact)
        if contact:
            pdf.cell(0, 10, " | ".join(contact), ln=True)

    reports_dir = user_reports_dir(session.user_id)
    filename = f"Report_{datetime.now().strftime('%Y-%m-%d_%H%M%S')}.pdf"
    filepath = reports_dir / filename
    pdf.output(str(filepath))
    return str(filepath)
