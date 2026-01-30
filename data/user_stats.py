"""
User Stats Manager - Stores per-user usage counters
===================================================
Keeps a fixed-size counters file per user.
"""

import json
import logging
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path

import config

logger = logging.getLogger(__name__)

# Directory for per-user stats
STATS_DIR = config.BASE_DIR / "stats"
STATS_DIR.mkdir(exist_ok=True)


@dataclass
class UserStats:
    """Fixed-size stats counters for a user."""
    version: int = 1
    reports_started: int = 0
    reports_created: int = 0
    reports_cancelled: int = 0
    locations_used: int = 0
    photos_added: int = 0
    voice_notes_added: int = 0
    text_notes_added: int = 0
    contacts_added: int = 0
    google_connected: int = 0
    google_disconnected: int = 0
    last_updated: str = ""

    def touch(self):
        self.last_updated = datetime.utcnow().isoformat(timespec="seconds") + "Z"


class UserStatsManager:
    """Manages per-user stats stored on disk."""

    def __init__(self):
        self._cache: dict[int, UserStats] = {}

    def _get_stats_path(self, user_id: int) -> Path:
        return STATS_DIR / f"stats_{user_id}.json"

    def get_stats(self, user_id: int) -> UserStats:
        if user_id in self._cache:
            return self._cache[user_id]

        stats_path = self._get_stats_path(user_id)
        if stats_path.exists():
            try:
                with open(stats_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                stats = UserStats(**data)
                self._cache[user_id] = stats
                return stats
            except Exception as e:
                logger.error(f"Failed to load stats for user {user_id}: {e}")

        stats = UserStats()
        self._cache[user_id] = stats
        return stats

    def save_stats(self, user_id: int, stats: UserStats):
        stats.touch()
        stats_path = self._get_stats_path(user_id)
        with open(stats_path, "w", encoding="utf-8") as f:
            json.dump(asdict(stats), f, ensure_ascii=False, indent=2)
        self._cache[user_id] = stats
        logger.info(f"Saved stats for user {user_id}")

    def increment(self, user_id: int, field: str, amount: int = 1):
        stats = self.get_stats(user_id)
        if not hasattr(stats, field):
            logger.warning(f"Unknown stats field '{field}' for user {user_id}")
            return
        current = getattr(stats, field)
        if not isinstance(current, int):
            logger.warning(f"Stats field '{field}' is not int for user {user_id}")
            return
        setattr(stats, field, current + amount)
        self.save_stats(user_id, stats)


# Singleton instance
user_stats = UserStatsManager()
