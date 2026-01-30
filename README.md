# DocBot Workspace

This folder contains:

- `TelegramDocBot/` — legacy Telegram bot codebase (kept for reference)
- `DocBotApp/` — new app + backend scaffold (fresh build)

## Quick Start (DocBotApp)

Backend:
- `cd DocBotApp/DocBotApp/backend`
- `pip install -r requirements.txt`
- `uvicorn api.main:app --reload --port 8000 --app-dir .`

App:
- `cd DocBotApp/DocBotApp/app`
- `flutter create .` (first time only)
- `flutter pub get`
- `flutter run`
