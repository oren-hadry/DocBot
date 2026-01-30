"""
Conversation States
===================
Defines all conversation states for the bot handlers.
"""

from enum import Enum, auto


class SetupState(Enum):
    """States for user setup conversation."""
    WAITING_LOGO = auto()
    WAITING_COMPANY_NAME = auto()
    WAITING_CONTACT_INFO = auto()


class ReportState(Enum):
    """States for report creation conversation."""
    WAITING_LOCATION = auto()
    SELECTING_PARTICIPANTS = auto()
    COLLECTING_CONTENT = auto()
    SELECTING_CLIENT = auto()


class ContactState(Enum):
    """States for contact management conversation."""
    WAITING_NAME = auto()
    WAITING_EMAIL = auto()
    WAITING_ORG = auto()
