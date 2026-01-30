"""
Session Manager - Manages active report sessions
=================================================
Stores temporary data while user builds a report.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


@dataclass
class Finding:
    """A single finding with description and photos."""
    description: str
    photos: list[str] = field(default_factory=list)  # Photo file paths
    severity: str = "normal"  # normal, important, critical


@dataclass
class ReportSession:
    """Active report session for a user."""
    user_id: int
    created_at: datetime = field(default_factory=datetime.now)
    
    # Report metadata
    location: str = ""  # e.g., "Hadera East Station"
    subject: str = ""  # Full subject line
    general_description: str = ""
    
    # Participants
    participant_ids: list[str] = field(default_factory=list)  # Contact IDs who attended
    cc_ids: list[str] = field(default_factory=list)  # Contact IDs for CC (didn't attend)
    
    # Content - legacy simple mode
    photos: list[str] = field(default_factory=list)  # File paths
    voice_notes: list[str] = field(default_factory=list)  # Transcribed text
    text_notes: list[str] = field(default_factory=list)
    
    # Content - structured findings mode
    findings: list[Finding] = field(default_factory=list)
    
    # Client branding
    client_logo_path: Optional[str] = None  # If report is for a client
    client_name: Optional[str] = None
    
    # Document settings
    classification: Optional[str] = None  # e.g., "Internal", "Confidential"
    
    def add_photo(self, path: str):
        """Add a photo to the session."""
        self.photos.append(path)
    
    def add_voice_note(self, transcription: str):
        """Add transcribed voice note."""
        self.voice_notes.append(transcription)
    
    def add_text_note(self, text: str):
        """Add a text note."""
        self.text_notes.append(text)
    
    def add_finding(self, description: str, photos: list[str] = None):
        """Add a structured finding."""
        finding = Finding(
            description=description,
            photos=photos or []
        )
        self.findings.append(finding)
    
    def get_all_notes(self) -> str:
        """Get all notes combined."""
        all_notes = []
        
        for i, note in enumerate(self.voice_notes, 1):
            all_notes.append(f"Voice note {i}: {note}")
        
        for i, note in enumerate(self.text_notes, 1):
            all_notes.append(f"Text note {i}: {note}")
        
        if self.general_description:
            all_notes.insert(0, f"General description: {self.general_description}")
        
        return "\n\n".join(all_notes)
    
    def is_empty(self) -> bool:
        """Check if session has any content."""
        return (
            not self.photos 
            and not self.voice_notes 
            and not self.text_notes
            and not self.findings
            and not self.general_description
        )
    
    def get_content_summary(self) -> str:
        """Get a summary of session content."""
        parts = []
        if self.location:
            parts.append(f"📍 {self.location}")
        if self.photos:
            parts.append(f"📷 {len(self.photos)}")
        if self.voice_notes:
            parts.append(f"🎤 {len(self.voice_notes)}")
        if self.text_notes:
            parts.append(f"📝 {len(self.text_notes)}")
        if self.participant_ids:
            parts.append(f"👥 {len(self.participant_ids)}")
        
        return " | ".join(parts) if parts else "-"


class SessionManager:
    """Manages report sessions for all users."""
    
    def __init__(self):
        self._sessions: dict[int, ReportSession] = {}
    
    def create_session(self, user_id: int) -> ReportSession:
        """Create a new session, replacing any existing one."""
        # Clean up old session if exists
        self.delete_session(user_id)
        
        session = ReportSession(user_id=user_id)
        self._sessions[user_id] = session
        logger.info(f"Created new session for user {user_id}")
        return session
    
    def get_session(self, user_id: int) -> Optional[ReportSession]:
        """Get existing session for user."""
        return self._sessions.get(user_id)
    
    def delete_session(self, user_id: int):
        """Delete session and clean up temp files."""
        session = self._sessions.pop(user_id, None)
        
        if session:
            # Clean up photo files
            for photo_path in session.photos:
                try:
                    Path(photo_path).unlink(missing_ok=True)
                except Exception as e:
                    logger.warning(f"Failed to delete temp file {photo_path}: {e}")
            
            logger.info(f"Deleted session for user {user_id}")
    
    def has_session(self, user_id: int) -> bool:
        """Check if user has an active session."""
        return user_id in self._sessions


# Singleton instance
session_manager = SessionManager()
