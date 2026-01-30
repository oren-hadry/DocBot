"""
Language Support Module
=======================
Load and manage language strings for the bot.
"""

import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Available languages
LANGUAGES = {
    "he": "עברית",
    "en": "English",
}

# Default language
DEFAULT_LANGUAGE = "he"

# Current loaded strings
_current_strings: dict = {}
_current_language: str = DEFAULT_LANGUAGE


def load_language(lang_code: str) -> bool:
    """
    Load language strings for the specified language.
    
    Args:
        lang_code: Language code ('he' or 'en')
        
    Returns:
        True if loaded successfully, False otherwise
    """
    global _current_strings, _current_language
    
    if lang_code not in LANGUAGES:
        logger.warning(f"Unknown language: {lang_code}, using default")
        lang_code = DEFAULT_LANGUAGE
    
    try:
        if lang_code == "he":
            from lang.he import STRINGS
        elif lang_code == "en":
            from lang.en import STRINGS
        else:
            from lang.he import STRINGS
        
        _current_strings = STRINGS
        _current_language = lang_code
        logger.info(f"Loaded language: {lang_code}")
        return True
        
    except ImportError as e:
        logger.error(f"Failed to load language {lang_code}: {e}")
        return False


def get(key: str, **kwargs) -> str:
    """
    Get a localized string by key.
    
    Args:
        key: The string key
        **kwargs: Format arguments
        
    Returns:
        The localized string, or the key if not found
    """
    if not _current_strings:
        load_language(DEFAULT_LANGUAGE)
    
    text = _current_strings.get(key, key)
    
    if kwargs:
        try:
            text = text.format(**kwargs)
        except KeyError as e:
            logger.warning(f"Missing format key {e} for string '{key}'")
    
    return text


def get_current_language() -> str:
    """Get the current language code."""
    return _current_language


def get_language_name(lang_code: Optional[str] = None) -> str:
    """Get the display name of a language."""
    code = lang_code or _current_language
    return LANGUAGES.get(code, code)


# Shortcut alias
_ = get


# Initialize with default language
load_language(DEFAULT_LANGUAGE)
