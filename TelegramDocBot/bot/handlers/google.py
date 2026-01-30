"""
Google Handlers
===============
Handles Google Drive connection: connect, disconnect.
"""

import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes

from lang import _ as t
from services.google_auth import google_auth
from data.user_stats import user_stats

logger = logging.getLogger(__name__)


async def connect_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Initiate Google OAuth."""
    user_id = update.effective_user.id
    
    if google_auth.is_user_connected(user_id):
        await update.message.reply_text(t("google_already_connected"))
        return
    
    auth_url = google_auth.get_auth_url(user_id)
    user_stats.increment(user_id, "google_connected")
    
    keyboard = [[InlineKeyboardButton(t("btn_connect"), url=auth_url)]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("google_connect_title") + "\n\n" + t("google_connect_instruction"),
        parse_mode="Markdown",
        reply_markup=reply_markup,
    )


async def disconnect_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Disconnect Google."""
    user_id = update.effective_user.id
    
    if google_auth.disconnect_user(user_id):
        user_stats.increment(user_id, "google_disconnected")
        await update.message.reply_text(t("google_disconnected"))
    else:
        await update.message.reply_text(t("google_not_connected"))
