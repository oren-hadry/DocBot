import json
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
    def get(self, user_id: int) -> UserStats:
        path = user_stats_file(user_id)
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                return UserStats(**json.load(f))
        return UserStats()

    def save(self, user_id: int, stats: UserStats) -> None:
        stats.touch()
        path = user_stats_file(user_id)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(asdict(stats), f, ensure_ascii=False, indent=2)

    def increment(self, user_id: int, field: str, amount: int = 1) -> None:
        stats = self.get(user_id)
        if hasattr(stats, field):
            setattr(stats, field, getattr(stats, field) + amount)
            self.save(user_id, stats)


stats_manager = StatsManager()
