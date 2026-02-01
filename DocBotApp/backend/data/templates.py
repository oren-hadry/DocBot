from dataclasses import dataclass


@dataclass(frozen=True)
class ReportTemplate:
    key: str
    title: str
    title_he: str


TEMPLATES = [
    ReportTemplate(key="INSPECTION_REPORT", title="Inspection Report", title_he="דוח פיקוח"),
    ReportTemplate(key="VISIT_SUMMARY", title="Visit Summary", title_he="סיכום ביקור"),
    ReportTemplate(key="HOME_ORGANIZER_REPORT", title="Home Organizer Report", title_he="דוח סידור בית"),
    ReportTemplate(key="QUOTE", title="Quote", title_he="הצעת מחיר"),
]


def get_template(key: str) -> ReportTemplate:
    for template in TEMPLATES:
        if template.key == key:
            return template
    return TEMPLATES[0]
