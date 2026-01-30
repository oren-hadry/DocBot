"""
Voice Transcriber - Converts voice messages to text using OpenAI Whisper
========================================================================
"""

import logging
from pathlib import Path
from openai import OpenAI

import config

logger = logging.getLogger(__name__)


class VoiceTranscriber:
    """Transcribes voice messages using OpenAI Whisper API."""
    
    def __init__(self):
        self.client = OpenAI(api_key=config.OPENAI_API_KEY)
    
    async def transcribe(self, audio_path: str) -> str:
        """
        Transcribe an audio file to text.
        
        Args:
            audio_path: Path to the audio file (ogg, mp3, wav, etc.)
            
        Returns:
            Transcribed text
        """
        logger.info(f"Transcribing: {audio_path}")
        
        audio_file = Path(audio_path)
        if not audio_file.exists():
            raise FileNotFoundError(f"Audio file not found: {audio_path}")
        
        # OpenAI Whisper API call
        with open(audio_file, "rb") as f:
            transcript = self.client.audio.transcriptions.create(
                model=config.WHISPER_MODEL,
                file=f,
                response_format="text",
            )
        
        logger.info(f"Transcription complete: {len(transcript)} chars")
        return transcript.strip()


# Singleton instance
voice_transcriber = VoiceTranscriber()
