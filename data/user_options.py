"""
User Options Manager - Stores per-user selectable options
========================================================
Keeps recent locations and other choices for each user.
"""

import json
import logging
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Optional

import config

logger = logging.getLogger(__name__)

# Directory for per-user options
OPTIONS_DIR = config.BASE_DIR / "options"
OPTIONS_DIR.mkdir(exist_ok=True)


@dataclass
class UserOptions:
    """Per-user saved options for quick selection."""
    locations: list[str] = field(default_factory=list)

    def add_location(self, location: str, max_items: int = 10):
        """Add a location to the recent list (deduped, most recent first)."""
        location = location.strip()
        if not location:
            return
        existing = [loc for loc in self.locations if loc.lower() != location.lower()]
        self.locations = [location] + existing
        if len(self.locations) > max_items:
            self.locations = self.locations[:max_items]


class UserOptionsManager:
    """Manages per-user options stored on disk."""

    def __init__(self):
        self._cache: dict[int, UserOptions] = {}

    def _get_options_path(self, user_id: int) -> Path:
        return OPTIONS_DIR / f"options_{user_id}.json"

    def get_options(self, user_id: int) -> UserOptions:
        if user_id in self._cache:
            return self._cache[user_id]

        options_path = self._get_options_path(user_id)
        if options_path.exists():
            try:
                with open(options_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                options = UserOptions(**data)
                self._cache[user_id] = options
                return options
            except Exception as e:
                logger.error(f"Failed to load options for user {user_id}: {e}")

        options = UserOptions()
        self._cache[user_id] = options
        return options

    def save_options(self, user_id: int, options: UserOptions):
        options_path = self._get_options_path(user_id)
        with open(options_path, "w", encoding="utf-8") as f:
            json.dump(asdict(options), f, ensure_ascii=False, indent=2)
        self._cache[user_id] = options
        logger.info(f"Saved options for user {user_id}")

    def add_location(self, user_id: int, location: str, max_items: int = 10):
        options = self.get_options(user_id)
        options.add_location(location, max_items=max_items)
        self.save_options(user_id, options)

    def get_locations(self, user_id: int) -> list[str]:
        return self.get_options(user_id).locations


# Singleton instance
user_options = UserOptionsManager()
