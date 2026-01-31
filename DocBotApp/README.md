# DocBotApp

Fresh app + backend scaffold for a simple inspection report flow.

## Backend (FastAPI)
- Install: `pip install -r backend/requirements.txt`
- Run: `uvicorn api.main:app --reload --port 8000 --app-dir backend`

### Environment
Copy `backend/.env.example` to `backend/.env` and update:
- `API_SECRET`
- `CORS_ORIGINS`
- `STORAGE_DIR` (optional)

## App (Flutter)
This is a minimal Flutter client. If Flutter is not initialized in the folder:
- `cd app`
- `flutter create .`
- `flutter pub get`
- `flutter run`

## Notes
- Word reports are generated server-side and saved per user in `backend/storage/<user_id>/reports/`.
- Storage is separated per user by path.
