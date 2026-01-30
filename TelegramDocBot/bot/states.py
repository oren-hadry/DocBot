"""
Conversation States
===================
Defines all conversation states for the bot handlers.
Each Enum has unique starting values to avoid conflicts when states
are used in the same ConversationHandler.
"""

from enum import Enum


class SetupState(Enum):
    """States for user setup conversation."""
    WAITING_LOGO = 100
    WAITING_COMPANY_NAME = 101
    WAITING_CONTACT_INFO = 102


class ReportState(Enum):
    """States for report creation conversation."""
    WAITING_LOCATION = 200
    SELECTING_PARTICIPANTS = 201
    COLLECTING_CONTENT = 202
    SELECTING_CLIENT = 203


class ContactState(Enum):
    """States for contact management conversation."""
    WAITING_NAME = 300
    WAITING_EMAIL = 301
    WAITING_ORG = 302
