"""
Bot Application
===============
Creates and configures the Telegram bot application.
"""

import logging
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    ConversationHandler,
    filters,
)

import config
from bot.states import SetupState, ReportState, ContactState
from bot.handlers import (
    # Start
    start_command,
    help_command,
    general_callback_handler,
    # Report
    new_report_command,
    report_receive_location,
    report_skip_location,
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
    # Contacts
    contacts_command,
    add_contact_start,
    contact_receive_name,
    contact_receive_email,
    contact_skip_email,
    contact_receive_org,
    contact_skip_org,
    cancel_contact,
    # Setup
    setup_command,
    setup_receive_logo,
    setup_skip_logo,
    setup_receive_company,
    setup_skip_company,
    setup_receive_contact,
    setup_skip_contact,
    mylogo_command,
    # Google
    connect_command,
    disconnect_command,
)

logger = logging.getLogger(__name__)


def create_application() -> Application:
    """Create and configure the bot application."""
    
    application = Application.builder().token(config.TELEGRAM_BOT_TOKEN).build()
    
    # ========================================================================
    # Conversation Handlers
    # ========================================================================
    
    # Report conversation handler
    report_handler = ConversationHandler(
        entry_points=[CommandHandler("new", new_report_command)],
        states={
            ReportState.WAITING_LOCATION.value: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, report_receive_location),
                CallbackQueryHandler(report_skip_location, pattern="^report_skip_location$"),
            ],
            ReportState.SELECTING_PARTICIPANTS.value: [
                CallbackQueryHandler(toggle_participant, pattern="^toggle_participant_"),
                CallbackQueryHandler(report_done_participants, pattern="^report_done_participants$"),
                CallbackQueryHandler(report_skip_participants, pattern="^report_skip_participants$"),
                CallbackQueryHandler(add_contact_start, pattern="^add_contact_from_report$"),
            ],
            ReportState.COLLECTING_CONTENT.value: [
                MessageHandler(filters.PHOTO, handle_photo),
                MessageHandler(filters.VOICE, handle_voice),
                MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_in_report),
                CallbackQueryHandler(create_report_callback, pattern="^create_report$"),
                CallbackQueryHandler(cancel_report_callback, pattern="^cancel_report$"),
            ],
        },
        fallbacks=[
            CommandHandler("cancel", cancel_command),
            CallbackQueryHandler(cancel_report_callback, pattern="^cancel_report$"),
        ],
        allow_reentry=True,
    )
    
    # Contact conversation handler
    contact_handler = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(add_contact_start, pattern="^add_contact$"),
            CallbackQueryHandler(add_contact_start, pattern="^add_contact_from_report$"),
        ],
        states={
            ContactState.WAITING_NAME.value: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, contact_receive_name),
            ],
            ContactState.WAITING_EMAIL.value: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, contact_receive_email),
                CallbackQueryHandler(contact_skip_email, pattern="^contact_skip_email$"),
            ],
            ContactState.WAITING_ORG.value: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, contact_receive_org),
                CallbackQueryHandler(contact_skip_org, pattern="^contact_skip_org$"),
            ],
        },
        fallbacks=[CommandHandler("cancel", cancel_contact)],
    )
    
    # Setup conversation handler
    setup_handler = ConversationHandler(
        entry_points=[CommandHandler("setup", setup_command)],
        states={
            SetupState.WAITING_LOGO.value: [
                MessageHandler(filters.PHOTO, setup_receive_logo),
                CallbackQueryHandler(setup_skip_logo, pattern="^setup_skip_logo$"),
            ],
            SetupState.WAITING_COMPANY_NAME.value: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, setup_receive_company),
                CallbackQueryHandler(setup_skip_company, pattern="^setup_skip_company$"),
            ],
            SetupState.WAITING_CONTACT_INFO.value: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, setup_receive_contact),
                CallbackQueryHandler(setup_skip_contact, pattern="^setup_skip_contact$"),
            ],
        },
        fallbacks=[CommandHandler("cancel", cancel_command)],
    )
    
    # ========================================================================
    # Register Handlers
    # ========================================================================
    
    # Basic commands
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    
    # Conversation handlers
    application.add_handler(report_handler)
    application.add_handler(contact_handler)
    application.add_handler(setup_handler)
    
    # Other commands
    application.add_handler(CommandHandler("contacts", contacts_command))
    application.add_handler(CommandHandler("status", status_command))
    application.add_handler(CommandHandler("cancel", cancel_command))
    application.add_handler(CommandHandler("connect", connect_command))
    application.add_handler(CommandHandler("disconnect", disconnect_command))
    application.add_handler(CommandHandler("mylogo", mylogo_command))
    
    # General callback handler (fallback)
    application.add_handler(CallbackQueryHandler(general_callback_handler))
    
    logger.info("Application configured with all handlers")
    
    return application
