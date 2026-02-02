import os
from datetime import datetime
from fpdf import FPDF
from data.report_manager import ReportSession
from data.user_auth import user_auth
from data.storage import user_reports_dir

class DocBotPDF(FPDF):
    def __init__(self, has_hebrew=False):
        super().__init__()
        self.has_hebrew = has_hebrew
        # Standard fonts don't support Hebrew well, fpdf2 needs a unicode font.
        # We'll try to find a system font or assume Arial is available if added.
        # For this environment, we'll use a built-in-like approach.

    def header(self):
        pass

    def footer(self):
        self.set_y(-15)
        self.set_font("Arial", "I", 8)
        self.cell(0, 10, f"Page {self.page_no()}", 0, 0, "C")

def generate_report_pdf(session: ReportSession, logo_path: str = None) -> str:
    has_hebrew = any(ch >= "\u0590" and ch <= "\u05FF" for ch in (session.location + session.title))
    
    pdf = DocBotPDF(has_hebrew=has_hebrew)
    # Attempt to add a Hebrew-friendly font if available
    # For now, we use standard fonts, but we set RTL alignment
    pdf.add_page()
    
    align = "R" if has_hebrew else "L"
    
    if logo_path and os.path.exists(logo_path):
        pdf.image(logo_path, x=80, w=50)
        pdf.ln(10)

    pdf.set_font("Arial", "B", 16)
    pdf.cell(0, 10, session.title, ln=True, align="C")
    pdf.set_font("Arial", "", 12)
    pdf.ln(5)
    
    pdf.set_font("Arial", "B", 12)
    pdf.cell(0, 10, f"{'Date' if not has_hebrew else 'תאריך'}: {datetime.now().strftime('%d/%m/%Y')}", ln=True, align=align)
    if session.location:
        pdf.cell(0, 10, f"{'Location' if not has_hebrew else 'מיקום'}: {session.location}", ln=True, align=align)
    if session.project_name:
        pdf.cell(0, 10, f"{'Project' if not has_hebrew else 'פרויקט'}: {session.project_name}", ln=True, align=align)
    
    pdf.ln(10)
    pdf.set_font("Arial", "B", 14)
    pdf.cell(0, 10, "Findings" if not has_hebrew else "ממצאים", ln=True, align=align)
    pdf.set_font("Arial", "", 11)
    
    for item in session.items:
        pdf.set_font("Arial", "B", 11)
        pdf.cell(0, 10, f"{'Item' if not has_hebrew else 'סעיף'} {item.number}: {item.description}", ln=True, align=align)
        pdf.set_font("Arial", "", 11)
        if item.notes:
            pdf.multi_cell(0, 10, f"{'Notes' if not has_hebrew else 'הערות'}: {item.notes}", align=align)
        
        photos = [p for p in session.photos if p.item_id == item.id]
        if photos:
            for p in photos:
                if os.path.exists(p.file_path):
                    pdf.image(p.file_path, w=100)
                    pdf.ln(5)
        pdf.ln(5)

    # Signature
    user = user_auth.get_by_id(session.user_id)
    if user and user.full_name:
        pdf.ln(10)
        
        if user.signature_path and os.path.exists(user.signature_path):
            pdf.image(user.signature_path, w=40)
            pdf.ln(5)
            
        pdf.line(10, pdf.get_y(), 200, pdf.get_y())
        pdf.ln(5)
        pdf.set_font("Arial", "B", 11)
        pdf.cell(0, 10, f"Written by: {user.full_name}", ln=True)
        pdf.set_font("Arial", "", 11)
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
