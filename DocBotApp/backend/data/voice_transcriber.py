import os
import json
from pathlib import Path
from typing import Optional
from datetime import datetime, timedelta

# OpenAI API for Whisper
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

# Usage limits
MAX_SECONDS_PER_REPORT = 30
MAX_SECONDS_PER_USER = 300  # 5 minutes total


def _get_usage_file(user_id: int) -> Path:
    """Get path to user's transcription usage file."""
    from data.storage import user_dir
    return user_dir(user_id) / "transcription_usage.json"


def _load_usage(user_id: int) -> dict:
    """Load user's transcription usage."""
    path = _get_usage_file(user_id)
    if path.exists():
        with open(path, "r") as f:
            return json.load(f)
    return {"total_seconds": 0, "current_report_seconds": 0, "last_reset": None}


def _save_usage(user_id: int, usage: dict) -> None:
    """Save user's transcription usage."""
    path = _get_usage_file(user_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(usage, f)


def reset_report_usage(user_id: int) -> None:
    """Reset the per-report usage counter (call when starting new report)."""
    usage = _load_usage(user_id)
    usage["current_report_seconds"] = 0
    _save_usage(user_id, usage)


def get_remaining_seconds(user_id: int) -> tuple[int, int]:
    """
    Get remaining seconds for transcription.
    Returns (remaining_for_report, remaining_total)
    """
    usage = _load_usage(user_id)
    report_remaining = max(0, MAX_SECONDS_PER_REPORT - usage.get("current_report_seconds", 0))
    total_remaining = max(0, MAX_SECONDS_PER_USER - usage.get("total_seconds", 0))
    return (report_remaining, total_remaining)


def check_usage_limit(user_id: int, audio_duration_seconds: float) -> tuple[bool, str]:
    """
    Check if user can transcribe more audio.
    Returns (allowed, message)
    """
    usage = _load_usage(user_id)
    
    current_report = usage.get("current_report_seconds", 0)
    total = usage.get("total_seconds", 0)
    
    if total >= MAX_SECONDS_PER_USER:
        return False, "transcription_limit_total"
    
    if current_report >= MAX_SECONDS_PER_REPORT:
        return False, "transcription_limit_report"
    
    return True, ""


def record_usage(user_id: int, duration_seconds: float) -> None:
    """Record transcription usage."""
    usage = _load_usage(user_id)
    usage["current_report_seconds"] = usage.get("current_report_seconds", 0) + duration_seconds
    usage["total_seconds"] = usage.get("total_seconds", 0) + duration_seconds
    usage["last_used"] = datetime.utcnow().isoformat()
    _save_usage(user_id, usage)


def get_audio_duration(path: str) -> float:
    """Get audio file duration in seconds."""
    try:
        import wave
        with wave.open(path, 'rb') as audio:
            frames = audio.getnframes()
            rate = audio.getframerate()
            return frames / float(rate)
    except Exception:
        # For non-wav files, estimate based on file size (~16KB per second for compressed audio)
        try:
            size = os.path.getsize(path)
            return size / 16000
        except Exception:
            return 10  # Default estimate


def transcribe_audio(path: str, user_id: int = 0) -> tuple[str, str]:
    """
    Transcribe audio using OpenAI Whisper API.
    Returns (text, error_key) where error_key is empty on success.
    """
    if not OPENAI_API_KEY:
        return "", "transcription_no_api_key"
    
    # Check duration and limits
    duration = get_audio_duration(path)
    
    if user_id > 0:
        allowed, error_key = check_usage_limit(user_id, duration)
        if not allowed:
            return "", error_key
    
    try:
        import httpx
        
        with open(path, "rb") as audio_file:
            response = httpx.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                files={"file": audio_file},
                data={"model": "whisper-1"},
                timeout=60.0,
            )
        
        if response.status_code != 200:
            return "", "transcription_api_error"
        
        result = response.json()
        text = result.get("text", "").strip()
        
        # Record usage on success
        if user_id > 0:
            record_usage(user_id, duration)
        
        return text, ""
        
    except Exception as e:
        return "", "transcription_error"
