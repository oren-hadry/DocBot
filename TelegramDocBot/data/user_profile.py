"""
User Profile Manager - Stores user settings (logo, company info, template)
=========================================================================
Each user can customize their reports with their own branding.
"""

import json
import logging
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

import config

logger = logging.getLogger(__name__)

# Directory for user profiles
PROFILES_DIR = config.BASE_DIR / "profiles"
PROFILES_DIR.mkdir(exist_ok=True)


@dataclass
class UserProfile:
    """User's report customization settings."""
    user_id: int
    company_name: Optional[str] = None
    contact_info: Optional[str] = None
    logo_path: Optional[str] = None  # Path to saved logo file
    default_language: str = "auto"  # auto-detect from voice
    report_title_template: str = "Inspection Report"
    is_setup_complete: bool = False
    
    # Contacts for reports
    contacts: list = None  # List of {name, email, role}
    
    # Default client/organization
    default_client: Optional[str] = None  # e.g., "Israel Railways"
    
    def __post_init__(self):
        if self.contacts is None:
            self.contacts = []
    
    def get_company_display(self) -> str:
        """Get company name for display (with default)."""
        return self.company_name or "Company not set"
    
    def get_contact_display(self) -> str:
        """Get contact info for display (with default)."""
        return self.contact_info or "Contact info not set"
    
    def to_dict(self) -> dict:
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: dict) -> "UserProfile":
        return cls(**data)


class UserProfileManager:
    """Manages user profiles for report customization."""
    
    def __init__(self):
        self._cache: dict[int, UserProfile] = {}
    
    def _get_profile_path(self, user_id: int) -> Path:
        """Get the profile file path for a user."""
        return PROFILES_DIR / f"profile_{user_id}.json"
    
    def _get_logo_path(self, user_id: int) -> Path:
        """Get the logo file path for a user."""
        return PROFILES_DIR / f"logo_{user_id}.png"
    
    def get_profile(self, user_id: int) -> UserProfile:
        """Get or create a user profile."""
        # Check cache
        if user_id in self._cache:
            return self._cache[user_id]
        
        # Try to load from file
        profile_path = self._get_profile_path(user_id)
        if profile_path.exists():
            try:
                with open(profile_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                profile = UserProfile.from_dict(data)
                self._cache[user_id] = profile
                return profile
            except Exception as e:
                logger.error(f"Failed to load profile for user {user_id}: {e}")
        
        # Create new profile
        profile = UserProfile(user_id=user_id)
        self._cache[user_id] = profile
        return profile
    
    def save_profile(self, profile: UserProfile):
        """Save a user profile to disk."""
        profile_path = self._get_profile_path(profile.user_id)
        
        with open(profile_path, "w", encoding="utf-8") as f:
            json.dump(profile.to_dict(), f, ensure_ascii=False, indent=2)
        
        self._cache[profile.user_id] = profile
        logger.info(f"Saved profile for user {profile.user_id}")
    
    def save_logo(self, user_id: int, logo_data: bytes) -> str:
        """Save user's logo and return the path."""
        logo_path = self._get_logo_path(user_id)
        
        with open(logo_path, "wb") as f:
            f.write(logo_data)
        
        logger.info(f"Saved logo for user {user_id}")
        return str(logo_path)
    
    def has_logo(self, user_id: int) -> bool:
        """Check if user has a logo saved."""
        return self._get_logo_path(user_id).exists()
    
    def get_logo_path(self, user_id: int) -> Optional[str]:
        """Get path to user's logo if exists."""
        logo_path = self._get_logo_path(user_id)
        return str(logo_path) if logo_path.exists() else None
    
    def is_setup_complete(self, user_id: int) -> bool:
        """Check if user has completed initial setup."""
        profile = self.get_profile(user_id)
        return profile.is_setup_complete
    
    def delete_profile(self, user_id: int) -> bool:
        """Delete user's profile and logo."""
        deleted = False
        
        # Delete profile file
        profile_path = self._get_profile_path(user_id)
        if profile_path.exists():
            profile_path.unlink()
            deleted = True
        
        # Delete logo file
        logo_path = self._get_logo_path(user_id)
        if logo_path.exists():
            logo_path.unlink()
        
        # Remove from cache
        if user_id in self._cache:
            del self._cache[user_id]
        
        return deleted


# Singleton instance
profile_manager = UserProfileManager()
