import os
from functools import lru_cache
from typing import Optional

import whisper


@lru_cache
def _get_model():
    model_name = os.getenv("WHISPER_MODEL", "base")
    return whisper.load_model(model_name)


def transcribe_audio(path: str, language: Optional[str] = None) -> str:
    model = _get_model()
    options = {"task": "transcribe", "temperature": 0.0, "beam_size": 5}
    if language:
        normalized = language.lower()
        if normalized == "iw":
            normalized = "he"
        options["language"] = normalized
    result = model.transcribe(path, **options)
    return (result.get("text") or "").strip()
