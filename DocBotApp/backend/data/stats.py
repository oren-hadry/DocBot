import json
import re
from dataclasses import dataclass, asdict
from datetime import datetime

from data.storage import user_stats_file


@dataclass
class UserStats:
    reports_started: int = 0
    reports_created: int = 0
    items_added: int = 0
    photos_added: int = 0
    last_updated: str = ""

    def touch(self):
        self.last_updated = datetime.utcnow().isoformat(timespec="seconds") + "Z"


class StatsManager:
    def _recover_from_text(self, text: str) -> UserStats | None:
        if not text:
            return None
        # Try to parse the largest JSON object in the text.
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            try:
                data = json.loads(text[start : end + 1])
                return UserStats(**data)
            except Exception:
                pass
        # Fallback: recover numeric fields with regex.
        def _find_int(key: str) -> int | None:
            match = re.search(rf'"{key}"\s*:\s*(\d+)', text)
            return int(match.group(1)) if match else None

        recovered = {}
        for key in ["reports_started", "reports_created", "items_added", "photos_added"]:
            value = _find_int(key)
            if value is not None:
                recovered[key] = value
        if not recovered:
            return None
        last_updated_match = re.search(r'"last_updated"\s*:\s*"([^"]*)"', text)
        if last_updated_match:
            recovered["last_updated"] = last_updated_match.group(1)
        return UserStats(**recovered)

    def get(self, user_id: int) -> UserStats:
        path = user_stats_file(user_id)
        if path.exists():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    content = f.read()
                data = json.loads(content)
                return UserStats(**data)
            except Exception:
                recovered = self._recover_from_text(content if "content" in locals() else "")
                if recovered is not None:
                    self.save(user_id, recovered)
                    return recovered
                try:
                    path.unlink(missing_ok=True)
                except Exception:
                    pass
                return UserStats()
        return UserStats()

    def save(self, user_id: int, stats: UserStats) -> None:
        stats.touch()
        path = user_stats_file(user_id)
        tmp_path = path.with_suffix(".tmp")
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(asdict(stats), f, ensure_ascii=False, indent=2)
        tmp_path.replace(path)

    def increment(self, user_id: int, field: str, amount: int = 1) -> None:
        stats = self.get(user_id)
        if hasattr(stats, field):
            setattr(stats, field, getattr(stats, field) + amount)
            self.save(user_id, stats)


stats_manager = StatsManager()
