"""
Google Auth Manager - Handles OAuth2 for Google Drive/Docs
==========================================================
Each user authenticates with their own Google account.
Tokens are stored securely per user.
"""

import json
import logging
from pathlib import Path
from typing import Optional

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from google.auth.transport.requests import Request

import config

logger = logging.getLogger(__name__)


class GoogleAuthManager:
    """Manages Google OAuth2 authentication for multiple users."""
    
    def __init__(self):
        # Ensure token directory exists
        config.GOOGLE_TOKEN_DIR.mkdir(parents=True, exist_ok=True)
        
        # Check for credentials file
        if not config.GOOGLE_CREDENTIALS_FILE.exists():
            logger.warning(
                f"Google credentials file not found: {config.GOOGLE_CREDENTIALS_FILE}\n"
                "Please download OAuth2 credentials from Google Cloud Console."
            )
    
    def _get_token_path(self, user_id: int) -> Path:
        """Get the token file path for a specific user."""
        return config.GOOGLE_TOKEN_DIR / f"token_{user_id}.json"
    
    def is_user_connected(self, user_id: int) -> bool:
        """Check if user has valid Google credentials."""
        token_path = self._get_token_path(user_id)
        
        if not token_path.exists():
            return False
        
        try:
            creds = self._load_credentials(user_id)
            return creds is not None and creds.valid
        except:
            return False
    
    def _load_credentials(self, user_id: int) -> Optional[Credentials]:
        """Load and refresh credentials for a user."""
        token_path = self._get_token_path(user_id)
        
        if not token_path.exists():
            return None
        
        try:
            creds = Credentials.from_authorized_user_file(
                str(token_path), 
                config.GOOGLE_SCOPES
            )
            
            # Refresh if expired
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
                # Save refreshed token
                self._save_credentials(user_id, creds)
            
            return creds if creds and creds.valid else None
            
        except Exception as e:
            logger.error(f"Failed to load credentials for user {user_id}: {e}")
            return None
    
    def _save_credentials(self, user_id: int, creds: Credentials):
        """Save credentials to file."""
        token_path = self._get_token_path(user_id)
        
        with open(token_path, "w") as f:
            f.write(creds.to_json())
        
        logger.info(f"Saved credentials for user {user_id}")
    
    def get_auth_url(self, user_id: int) -> str:
        """
        Generate OAuth authorization URL for a user.
        
        In production, this should redirect to a web server that handles
        the OAuth callback. For local development, we use a simpler flow.
        """
        if not config.GOOGLE_CREDENTIALS_FILE.exists():
            raise FileNotFoundError(
                "Google credentials file not found. "
                "Please download from Google Cloud Console."
            )
        
        flow = Flow.from_client_secrets_file(
            str(config.GOOGLE_CREDENTIALS_FILE),
            scopes=config.GOOGLE_SCOPES,
            redirect_uri="urn:ietf:wg:oauth:2.0:oob"  # For local/manual flow
        )
        
        auth_url, _ = flow.authorization_url(
            access_type="offline",
            include_granted_scopes="true",
            state=str(user_id),  # Pass user_id in state
            prompt="consent",  # Always show consent screen
        )
        
        return auth_url
    
    def complete_auth(self, user_id: int, auth_code: str) -> bool:
        """
        Complete OAuth flow with authorization code.
        
        Args:
            user_id: Telegram user ID
            auth_code: Authorization code from Google
            
        Returns:
            True if successful, False otherwise
        """
        try:
            flow = Flow.from_client_secrets_file(
                str(config.GOOGLE_CREDENTIALS_FILE),
                scopes=config.GOOGLE_SCOPES,
                redirect_uri="urn:ietf:wg:oauth:2.0:oob"
            )
            
            flow.fetch_token(code=auth_code)
            creds = flow.credentials
            
            self._save_credentials(user_id, creds)
            logger.info(f"User {user_id} successfully authenticated with Google")
            
            return True
            
        except Exception as e:
            logger.error(f"Auth completion failed for user {user_id}: {e}")
            return False
    
    def get_user_credentials(self, user_id: int) -> Optional[Credentials]:
        """Get valid credentials for a user."""
        return self._load_credentials(user_id)
    
    def disconnect_user(self, user_id: int) -> bool:
        """Remove user's Google credentials."""
        token_path = self._get_token_path(user_id)
        
        if token_path.exists():
            token_path.unlink()
            logger.info(f"Disconnected Google for user {user_id}")
            return True
        
        return False


# Singleton instance
google_auth = GoogleAuthManager()
