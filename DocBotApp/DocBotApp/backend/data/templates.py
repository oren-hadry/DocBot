from dataclasses import dataclass


@dataclass(frozen=True)
class ReportTemplate:
    key: str
    title: str


TEMPLATES = [
    ReportTemplate(key="INSPECTION_REPORT", title="Inspection Report"),
    ReportTemplate(key="VISIT_SUMMARY", title="Visit Summary"),
    ReportTemplate(key="HOME_ORGANIZER_REPORT", title="Home Organizer Report"),
    ReportTemplate(key="QUOTE", title="Quote"),
]


def get_template(key: str) -> ReportTemplate:
    for template in TEMPLATES:
        if template.key == key:
            return template
    return TEMPLATES[0]
