# DocBotApp

Fresh app + backend scaffold for a simple inspection report flow.

## Structure
- `DocBotApp/backend/` — FastAPI backend (Word report generation)
- `DocBotApp/app/` — Flutter client (mobile-first)

## Backend
- `cd DocBotApp/backend`
- `pip install -r requirements.txt`
- `uvicorn api.main:app --reload --port 8000 --app-dir .`

## App
- `cd DocBotApp/app`
- `flutter create .` (first time only)
- `flutter pub get`
- `flutter run`

## Notes
- Word files are saved per user under `DocBotApp/backend/storage/<user_id>/reports/`.
- Storage is separated by user id.
