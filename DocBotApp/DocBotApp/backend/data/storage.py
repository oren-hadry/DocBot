from pathlib import Path

import config


def user_dir(user_id: int) -> Path:
    base = config.STORAGE_DIR / str(user_id)
    base.mkdir(parents=True, exist_ok=True)
    return base


def user_reports_dir(user_id: int) -> Path:
    reports = user_dir(user_id) / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    return reports


def user_temp_dir(user_id: int) -> Path:
    temp = user_dir(user_id) / "temp"
    temp.mkdir(parents=True, exist_ok=True)
    return temp


def user_contacts_file(user_id: int) -> Path:
    return user_dir(user_id) / "contacts.json"


def user_stats_file(user_id: int) -> Path:
    return user_dir(user_id) / "stats.json"
