#!/usr/bin/env python3
"""
DocBot - Telegram Bot for Inspection Reports
=============================================
Entry point for the application.

Usage:
    python main.py
"""

import logging
from telegram import Update

import config
import lang
from bot import create_application

# Setup logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=getattr(logging, config.LOG_LEVEL),
)
logger = logging.getLogger(__name__)

# Suppress httpx logging (contains bot token in URLs)
logging.getLogger("httpx").setLevel(logging.WARNING)


def main():
    """Start the bot."""
    # Validate configuration
    if not config.TELEGRAM_BOT_TOKEN:
        raise ValueError("TELEGRAM_BOT_TOKEN not set in .env file")
    if not config.OPENAI_API_KEY:
        raise ValueError("OPENAI_API_KEY not set in .env file")
    
    # Load language
    lang.load_language(config.BOT_LANGUAGE)
    logger.info(f"Language: {lang.get_language_name()}")
    
    # Create and run application
    logger.info("Starting DocBot...")
    application = create_application()
    
    logger.info("Bot is running! Press Ctrl+C to stop.")
    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
