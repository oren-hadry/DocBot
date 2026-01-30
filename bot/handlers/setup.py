"""
Setup Handlers
==============
Handles user profile setup: logo, company name, contact info.
"""

import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes, ConversationHandler

from lang import _ as t
from bot.states import SetupState
from data.user_profile import profile_manager

logger = logging.getLogger(__name__)


async def setup_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Start setup flow."""
    keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="setup_skip_logo")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("setup_title") + "\n\n" + t("setup_ask_logo"),
        parse_mode="Markdown",
        reply_markup=reply_markup,
    )
    return SetupState.WAITING_LOGO.value


async def setup_receive_logo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive logo."""
    user_id = update.effective_user.id
    
    if update.message.photo:
        photo = update.message.photo[-1]
        file = await context.bot.get_file(photo.file_id)
        logo_bytes = await file.download_as_bytearray()
        logo_path = profile_manager.save_logo(user_id, bytes(logo_bytes))
        
        profile = profile_manager.get_profile(user_id)
        profile.logo_path = logo_path
        profile_manager.save_profile(profile)
        
        keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="setup_skip_company")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(
            t("setup_logo_saved") + "\n\n" + t("setup_ask_company"),
            reply_markup=reply_markup,
        )
        return SetupState.WAITING_COMPANY_NAME.value
    
    await update.message.reply_text(t("setup_send_image"))
    return SetupState.WAITING_LOGO.value


async def setup_skip_logo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Skip logo."""
    query = update.callback_query
    await query.answer()
    
    keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="setup_skip_company")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await query.edit_message_text(
        t("setup_logo_skipped") + "\n\n" + t("setup_ask_company"),
        reply_markup=reply_markup
    )
    return SetupState.WAITING_COMPANY_NAME.value


async def setup_receive_company(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive company name."""
    user_id = update.effective_user.id
    profile = profile_manager.get_profile(user_id)
    profile.company_name = update.message.text.strip()
    profile_manager.save_profile(profile)
    
    keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="setup_skip_contact")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("setup_company_saved", name=profile.company_name) + "\n\n" + t("setup_ask_contact"),
        reply_markup=reply_markup,
    )
    return SetupState.WAITING_CONTACT_INFO.value


async def setup_skip_company(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Skip company name."""
    query = update.callback_query
    await query.answer()
    
    keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="setup_skip_contact")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await query.edit_message_text(
        t("setup_company_skipped") + "\n\n" + t("setup_ask_contact"),
        reply_markup=reply_markup
    )
    return SetupState.WAITING_CONTACT_INFO.value


async def setup_receive_contact(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive contact info."""
    user_id = update.effective_user.id
    profile = profile_manager.get_profile(user_id)
    profile.contact_info = update.message.text.strip()
    profile.is_setup_complete = True
    profile_manager.save_profile(profile)
    
    await update.message.reply_text(t("setup_complete"), parse_mode="Markdown")
    return ConversationHandler.END


async def setup_skip_contact(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Skip contact info."""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    profile = profile_manager.get_profile(user_id)
    profile.is_setup_complete = True
    profile_manager.save_profile(profile)
    
    await query.edit_message_text(t("setup_complete"), parse_mode="Markdown")
    return ConversationHandler.END


async def mylogo_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show user's logo."""
    user_id = update.effective_user.id
    logo_path = profile_manager.get_logo_path(user_id)
    
    if logo_path:
        await update.message.reply_photo(
            photo=open(logo_path, "rb"),
            caption=t("logo_current"),
        )
    else:
        await update.message.reply_text(t("logo_none"))
