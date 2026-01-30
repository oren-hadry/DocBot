"""
Configuration settings for DocBot
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Base directory
BASE_DIR = Path(__file__).parent

# Telegram settings
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")

# OpenAI settings
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
WHISPER_MODEL = "whisper-1"
GPT_MODEL = "gpt-4o-mini"  # Cost-effective model

# Google settings
GOOGLE_CREDENTIALS_FILE = BASE_DIR / "credentials.json"
GOOGLE_TOKEN_DIR = BASE_DIR / "tokens"  # Per-user tokens stored here
GOOGLE_SCOPES = [
    "https://www.googleapis.com/auth/drive.file",  # Only files created by the app
]

# Temp directory for downloaded files
TEMP_DIR = BASE_DIR / "temp"
TEMP_DIR.mkdir(exist_ok=True)

# Report settings
REPORT_FOLDER_NAME = "DocBot Reports"  # Folder name in user's Google Drive
MAX_IMAGES_PER_REPORT = 20
MAX_VOICE_DURATION_SECONDS = 300  # 5 minutes

# Logging
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Language settings
# Options: "he" (Hebrew), "en" (English)
BOT_LANGUAGE = os.getenv("BOT_LANGUAGE", "he")
