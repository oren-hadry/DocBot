"""
Bot Handlers
============
Export all handlers for easy import.
"""

from bot.handlers.start import (
    start_command,
    help_command,
    general_callback_handler,
)

from bot.handlers.report import (
    new_report_command,
    report_receive_location,
    report_skip_location,
    show_participant_selection,
    toggle_participant,
    report_done_participants,
    report_skip_participants,
    handle_photo,
    handle_voice,
    handle_text_in_report,
    create_report_callback,
    cancel_report_callback,
    status_command,
    cancel_command,
)

from bot.handlers.contacts import (
    contacts_command,
    add_contact_start,
    contact_receive_name,
    contact_receive_email,
    contact_skip_email,
    contact_receive_org,
    contact_skip_org,
    cancel_contact,
)

from bot.handlers.setup import (
    setup_command,
    setup_receive_logo,
    setup_skip_logo,
    setup_receive_company,
    setup_skip_company,
    setup_receive_contact,
    setup_skip_contact,
    mylogo_command,
)

from bot.handlers.google import (
    connect_command,
    disconnect_command,
)

__all__ = [
    # Start
    "start_command",
    "help_command",
    "general_callback_handler",
    # Report
    "new_report_command",
    "report_receive_location",
    "report_skip_location",
    "show_participant_selection",
    "toggle_participant",
    "report_done_participants",
    "report_skip_participants",
    "handle_photo",
    "handle_voice",
    "handle_text_in_report",
    "create_report_callback",
    "cancel_report_callback",
    "status_command",
    "cancel_command",
    # Contacts
    "contacts_command",
    "add_contact_start",
    "contact_receive_name",
    "contact_receive_email",
    "contact_skip_email",
    "contact_receive_org",
    "contact_skip_org",
    "cancel_contact",
    # Setup
    "setup_command",
    "setup_receive_logo",
    "setup_skip_logo",
    "setup_receive_company",
    "setup_skip_company",
    "setup_receive_contact",
    "setup_skip_contact",
    "mylogo_command",
    # Google
    "connect_command",
    "disconnect_command",
]
