"""
Start & Help Handlers
=====================
Handles /start and /help commands.
"""

import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes

from lang import _ as t
from services.google_auth import google_auth
from data.user_profile import profile_manager

logger = logging.getLogger(__name__)


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start - simple welcome."""
    user = update.effective_user
    user_id = user.id
    
    logger.info(f"User {user_id} ({user.first_name}) started the bot")
    
    # Check if first time
    if not profile_manager.is_setup_complete(user_id):
        profile = profile_manager.get_profile(user_id)
        profile.is_setup_complete = True
        profile_manager.save_profile(profile)
        
        if not google_auth.is_user_connected(user_id):
            keyboard = [
                [InlineKeyboardButton(t("btn_connect_google"), callback_data="start_connect")],
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)
            
            await update.message.reply_text(
                t("welcome_message") + t("important_connect_google"),
                parse_mode="Markdown",
                reply_markup=reply_markup,
            )
            return
    
    keyboard = [[InlineKeyboardButton(t("btn_start_report"), callback_data="start_new_report")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("welcome_message"),
        parse_mode="Markdown",
        reply_markup=reply_markup,
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command."""
    await update.message.reply_text(t("help_message"), parse_mode="Markdown")


async def general_callback_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle general callbacks not in conversation."""
    query = update.callback_query
    await query.answer()
    
    data = query.data
    
    if data == "start_connect":
        await query.message.reply_text(t("send_connect"))
    elif data == "start_new_report":
        await query.message.reply_text(t("send_new"))
