import json
from datetime import datetime

from data.storage import user_audit_file


def log_event(user_id: int, event_type: str, details: dict | None = None) -> None:
    payload = {
        "ts": datetime.utcnow().isoformat(timespec="seconds") + "Z",
        "event": event_type,
        "details": details or {},
    }
    path = user_audit_file(user_id)
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")
