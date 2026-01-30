import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

API_SECRET = os.getenv("API_SECRET", "change_me")
API_TOKEN_EXPIRE_MINUTES = int(os.getenv("API_TOKEN_EXPIRE_MINUTES", "10080"))

# Storage
STORAGE_DIR = BASE_DIR / "storage"
USERS_FILE = BASE_DIR / "users" / "users.json"

# Reports
MAX_IMAGES_PER_REPORT = 50
