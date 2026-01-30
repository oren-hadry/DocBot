"""
Contacts Handlers
=================
Handles contact management: list, add, delete.
"""

import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes, ConversationHandler

from lang import _ as t
from bot.states import ContactState
from data.contacts_manager import contacts_manager, Contact
from bot.handlers.report import show_participant_selection

logger = logging.getLogger(__name__)


async def contacts_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show contacts management."""
    user_id = update.effective_user.id
    contacts = contacts_manager.get_contacts(user_id)
    
    if not contacts:
        keyboard = [[InlineKeyboardButton(t("btn_add_contact"), callback_data="add_contact")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(
            t("contacts_empty"),
            parse_mode="Markdown",
            reply_markup=reply_markup,
        )
        return
    
    text = t("contacts_title") + "\n\n"
    for c in contacts:
        text += f"• {c.name}"
        if c.organization:
            text += f" ({c.organization})"
        if c.email:
            text += f"\n  📧 {c.email}"
        text += "\n"
    
    keyboard = [
        [InlineKeyboardButton(t("btn_add_contact"), callback_data="add_contact")],
        [InlineKeyboardButton(t("btn_delete"), callback_data="delete_contact_menu")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(text, parse_mode="Markdown", reply_markup=reply_markup)


async def add_contact_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Start adding a new contact."""
    query = update.callback_query
    await query.answer()
    
    context.user_data["adding_from_report"] = "from_report" in query.data
    
    await query.edit_message_text(
        t("add_contact_title") + "\n\n" + t("ask_name"),
        parse_mode="Markdown"
    )
    return ContactState.WAITING_NAME.value


async def contact_receive_name(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive contact name."""
    context.user_data["new_contact_name"] = update.message.text.strip()
    
    keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="contact_skip_email")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("name_saved", name=context.user_data['new_contact_name']) + "\n\n" + t("ask_email"),
        reply_markup=reply_markup,
    )
    return ContactState.WAITING_EMAIL.value


async def contact_receive_email(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive contact email."""
    context.user_data["new_contact_email"] = update.message.text.strip()
    
    keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="contact_skip_org")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("email_saved", email=context.user_data['new_contact_email']) + "\n\n" + t("ask_organization"),
        reply_markup=reply_markup,
    )
    return ContactState.WAITING_ORG.value


async def contact_skip_email(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Skip email."""
    query = update.callback_query
    await query.answer()
    
    context.user_data["new_contact_email"] = None
    
    keyboard = [[InlineKeyboardButton(t("btn_skip"), callback_data="contact_skip_org")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await query.edit_message_text(
        t("email_skipped") + "\n\n" + t("ask_organization"),
        reply_markup=reply_markup,
    )
    return ContactState.WAITING_ORG.value


async def contact_receive_org(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive organization and save contact."""
    user_id = update.effective_user.id
    org = update.message.text.strip()
    
    return await save_new_contact(update, context, user_id, org)


async def contact_skip_org(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Skip organization and save contact."""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    return await save_new_contact(update, context, user_id, None, from_callback=True)


async def save_new_contact(update, context, user_id, org, from_callback=False):
    """Save the new contact."""
    contact = Contact(
        id=contacts_manager.generate_id(user_id),
        name=context.user_data.get("new_contact_name", ""),
        email=context.user_data.get("new_contact_email"),
        organization=org,
    )
    
    contacts_manager.add_contact(user_id, contact)
    
    context.user_data.pop("new_contact_name", None)
    context.user_data.pop("new_contact_email", None)
    
    message = t("contact_added", name=contact.display_name())
    
    if context.user_data.pop("adding_from_report", False):
        if "selected_participants" not in context.user_data:
            context.user_data["selected_participants"] = set()
        context.user_data["selected_participants"].add(contact.id)
        
        message += t("returning_to_selection")
        
        if from_callback:
            await update.callback_query.edit_message_text(message, parse_mode="Markdown")
        else:
            await update.message.reply_text(message, parse_mode="Markdown")
        
        # Pass the correct from_callback value based on how we got here
        return await show_participant_selection(update, context, from_callback=from_callback)
    
    if from_callback:
        await update.callback_query.edit_message_text(message, parse_mode="Markdown")
    else:
        await update.message.reply_text(message, parse_mode="Markdown")
    
    return ConversationHandler.END


async def cancel_contact(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Cancel contact addition."""
    context.user_data.pop("new_contact_name", None)
    context.user_data.pop("new_contact_email", None)
    context.user_data.pop("adding_from_report", None)
    
    await update.message.reply_text(t("cancelled"))
    return ConversationHandler.END
