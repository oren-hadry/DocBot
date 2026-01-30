"""
Contacts Handlers
=================
Handles contact management: list, add, delete.
"""

import logging
import re
from typing import Optional
from telegram import (
    Update,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    ReplyKeyboardRemove,
)
from telegram.ext import ContextTypes, ConversationHandler

from lang import _ as t
from bot.states import ContactState
from data.contacts_manager import contacts_manager, Contact
from data.user_stats import user_stats
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
        if c.phone:
            text += f"\n  📞 {c.phone}"
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
        t("add_contact_title") + "\n\n" + t("ask_name_or_share"),
        parse_mode="Markdown"
    )
    return ContactState.WAITING_NAME.value


def _extract_email_from_vcard(vcard: Optional[str]) -> Optional[str]:
    if not vcard:
        return None
    match = re.search(r"EMAIL[^:]*:([^\n\r]+)", vcard, re.IGNORECASE)
    if not match:
        return None
    email = match.group(1).strip()
    return email if email else None


async def contact_receive_shared(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive a shared contact from Telegram."""
    user_id = update.effective_user.id
    contact = update.message.contact
    
    if not contact:
        await update.message.reply_text(t("ask_name_or_share"))
        return ContactState.WAITING_NAME.value
    
    if contact.user_id == user_id:
        await update.message.reply_text(t("contact_share_not_supported"), reply_markup=ReplyKeyboardRemove())
        return ContactState.WAITING_NAME.value
    
    name_parts = [contact.first_name or "", contact.last_name or ""]
    name = " ".join(part for part in name_parts if part).strip() or t("contact_unknown_name")
    email = _extract_email_from_vcard(contact.vcard)
    
    new_contact = Contact(
        id=contacts_manager.generate_id(user_id),
        name=name,
        email=email,
        phone=contact.phone_number,
        organization=None,
    )
    
    await _save_contact_object(update, context, user_id, new_contact)
    return ConversationHandler.END


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
    
    await _save_contact_object(update, context, user_id, contact, from_callback=from_callback)
    
    context.user_data.pop("new_contact_name", None)
    context.user_data.pop("new_contact_email", None)
    
    return ConversationHandler.END


async def _save_contact_object(update, context, user_id, contact: Contact, from_callback: bool = False):
    """Save a contact and handle report flow return."""
    contacts_manager.add_contact(user_id, contact)
    user_stats.increment(user_id, "contacts_added")
    
    message = t("contact_added", name=contact.display_name())
    reply_markup = ReplyKeyboardRemove()
    
    if context.user_data.pop("adding_from_report", False):
        if "selected_participants" not in context.user_data:
            context.user_data["selected_participants"] = set()
        context.user_data["selected_participants"].add(contact.id)
        
        message += t("returning_to_selection")
        
        if from_callback:
            await update.callback_query.message.reply_text(
                message,
                parse_mode="Markdown",
                reply_markup=reply_markup,
            )
        else:
            await update.message.reply_text(message, parse_mode="Markdown", reply_markup=reply_markup)
        
        return await show_participant_selection(update, context, from_callback=from_callback)
    
    if from_callback:
        await update.callback_query.message.reply_text(
            message,
            parse_mode="Markdown",
            reply_markup=reply_markup,
        )
    else:
        await update.message.reply_text(message, parse_mode="Markdown", reply_markup=reply_markup)


async def cancel_contact(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Cancel contact addition."""
    context.user_data.pop("new_contact_name", None)
    context.user_data.pop("new_contact_email", None)
    context.user_data.pop("adding_from_report", None)
    
    await update.message.reply_text(t("cancelled"), reply_markup=ReplyKeyboardRemove())
    return ConversationHandler.END
