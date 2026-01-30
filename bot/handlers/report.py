"""
Report Handlers
===============
Handles report creation flow: location, participants, content, generation.
"""

import logging
import os
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes, ConversationHandler

import config
from lang import _ as t
from bot.states import ReportState
from services.voice_transcriber import voice_transcriber
from services.word_generator import word_generator
from data.session_manager import session_manager
from data.contacts_manager import contacts_manager
from data.user_profile import profile_manager
from data.user_options import user_options
from data.user_stats import user_stats

logger = logging.getLogger(__name__)


# ============================================================================
# Report Start & Location
# ============================================================================

async def new_report_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Start new report - ask for location."""
    user_id = update.effective_user.id
    
    session_manager.create_session(user_id)
    user_stats.increment(user_id, "reports_started")
    
    locations = user_options.get_locations(user_id)[:5]
    
    keyboard = []
    for i, loc in enumerate(locations):
        keyboard.append([
            InlineKeyboardButton(loc, callback_data=f"report_location_{i}")
        ])
    keyboard.append([InlineKeyboardButton(t("btn_skip"), callback_data="report_skip_location")])
    reply_markup = InlineKeyboardMarkup(keyboard)
    context.user_data["location_choices"] = locations
    
    await update.message.reply_text(
        t("new_report_title") + "\n\n" + (t("ask_location_with_choices") if locations else t("ask_location")),
        parse_mode="Markdown",
        reply_markup=reply_markup,
    )
    return ReportState.WAITING_LOCATION.value


async def report_receive_location(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Receive location and move to participant selection."""
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    if session:
        session.location = update.message.text.strip()
        user_options.add_location(user_id, session.location)
        user_stats.increment(user_id, "locations_used")
    
    context.user_data.pop("location_choices", None)
    
    return await show_participant_selection(update, context)


async def report_select_location(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Select a saved location from inline buttons."""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    try:
        index = int(query.data.replace("report_location_", ""))
    except ValueError:
        await query.edit_message_text(t("ask_location"))
        return ReportState.WAITING_LOCATION.value
    
    locations = context.user_data.get("location_choices", [])
    if index < 0 or index >= len(locations):
        await query.edit_message_text(t("ask_location"))
        return ReportState.WAITING_LOCATION.value
    
    location = locations[index]
    if session:
        session.location = location
        user_options.add_location(user_id, location)
        user_stats.increment(user_id, "locations_used")
    
    context.user_data.pop("location_choices", None)
    
    await query.edit_message_text(t("location_selected", location=location))
    return await show_participant_selection(query.message, context, from_callback=True)


async def report_skip_location(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Skip location."""
    query = update.callback_query
    await query.answer()
    await query.edit_message_text(t("location_not_specified"))
    context.user_data.pop("location_choices", None)
    return await show_participant_selection(update, context, from_callback=True)


# ============================================================================
# Participant Selection
# ============================================================================

async def show_participant_selection(update: Update, context: ContextTypes.DEFAULT_TYPE, from_callback=False) -> int:
    """Show participant selection keyboard."""
    user_id = update.effective_user.id
    contacts = contacts_manager.get_contacts(user_id)
    
    if "selected_participants" not in context.user_data:
        context.user_data["selected_participants"] = set()
    
    if not contacts:
        keyboard = [
            [InlineKeyboardButton(t("btn_add_contact"), callback_data="add_contact_from_report")],
            [InlineKeyboardButton(t("btn_continue_no_participants"), callback_data="report_skip_participants")],
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        message = t("select_participants_title") + "\n\n" + t("no_contacts_yet")
    else:
        selected = context.user_data.get("selected_participants", set())
        keyboard = []
        
        for contact in contacts:
            is_selected = contact.id in selected
            emoji = "✅" if is_selected else "⬜"
            keyboard.append([
                InlineKeyboardButton(
                    f"{emoji} {contact.short_display()}",
                    callback_data=f"toggle_participant_{contact.id}"
                )
            ])
        
        keyboard.append([InlineKeyboardButton(t("btn_add_new"), callback_data="add_contact_from_report")])
        keyboard.append([InlineKeyboardButton(t("btn_done_selection"), callback_data="report_done_participants")])
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        count = len(selected)
        message = t("select_participants_count", count=count) + "\n\n" + t("select_participants_instruction")
    
    if from_callback:
        await update.callback_query.message.reply_text(message, parse_mode="Markdown", reply_markup=reply_markup)
    else:
        await update.message.reply_text(message, parse_mode="Markdown", reply_markup=reply_markup)
    
    return ReportState.SELECTING_PARTICIPANTS.value


async def toggle_participant(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Toggle participant selection."""
    query = update.callback_query
    await query.answer()
    
    contact_id = query.data.replace("toggle_participant_", "")
    selected = context.user_data.get("selected_participants", set())
    
    if contact_id in selected:
        selected.discard(contact_id)
    else:
        selected.add(contact_id)
    
    context.user_data["selected_participants"] = selected
    
    user_id = update.effective_user.id
    contacts = contacts_manager.get_contacts(user_id)
    
    keyboard = []
    for contact in contacts:
        is_selected = contact.id in selected
        emoji = "✅" if is_selected else "⬜"
        keyboard.append([
            InlineKeyboardButton(
                f"{emoji} {contact.short_display()}",
                callback_data=f"toggle_participant_{contact.id}"
            )
        ])
    
    keyboard.append([InlineKeyboardButton(t("btn_add_new"), callback_data="add_contact_from_report")])
    keyboard.append([InlineKeyboardButton(t("btn_done_selection"), callback_data="report_done_participants")])
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    count = len(selected)
    
    await query.edit_message_text(
        t("select_participants_count", count=count) + "\n\n" + t("select_participants_instruction"),
        parse_mode="Markdown",
        reply_markup=reply_markup,
    )
    
    return ReportState.SELECTING_PARTICIPANTS.value


async def report_done_participants(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Finish participant selection, move to content collection."""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    selected = context.user_data.get("selected_participants", set())
    if session:
        session.participant_ids = list(selected)
    
    context.user_data.pop("selected_participants", None)
    
    if selected:
        contacts = contacts_manager.get_contacts_by_ids(user_id, list(selected))
        names = ", ".join(c.name for c in contacts)
        participants_text = t("participants_selected", names=names)
    else:
        participants_text = t("participants_not_specified")
    
    await query.edit_message_text(participants_text)
    
    return await show_content_collection(query.message, context)


async def report_skip_participants(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Skip participant selection."""
    query = update.callback_query
    await query.answer()
    await query.edit_message_text(t("participants_not_specified"))
    
    return await show_content_collection(query.message, context)


async def show_content_collection(message, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Show content collection instructions."""
    keyboard = [
        [InlineKeyboardButton(t("btn_create_report"), callback_data="create_report")],
        [InlineKeyboardButton(t("btn_cancel"), callback_data="cancel_report")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await message.reply_text(
        t("content_instructions"),
        parse_mode="Markdown",
        reply_markup=reply_markup,
    )
    
    return ReportState.COLLECTING_CONTENT.value


# ============================================================================
# Content Handlers (Photos, Voice, Text)
# ============================================================================

async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle incoming photos."""
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    if not session:
        await update.message.reply_text(t("no_active_report"))
        return ConversationHandler.END
    
    photo = update.message.photo[-1]
    file = await context.bot.get_file(photo.file_id)
    
    photo_path = config.TEMP_DIR / f"{user_id}_{photo.file_unique_id}.jpg"
    await file.download_to_drive(photo_path)
    session.add_photo(str(photo_path))
    user_stats.increment(user_id, "photos_added")
    
    count = len(session.photos)
    keyboard = [
        [InlineKeyboardButton(t("btn_create_report"), callback_data="create_report")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("photo_received", count=count),
        reply_markup=reply_markup,
    )
    
    return ReportState.COLLECTING_CONTENT.value


async def handle_voice(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle incoming voice messages."""
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    if not session:
        await update.message.reply_text(t("no_active_report"))
        return ConversationHandler.END
    
    duration = update.message.voice.duration
    if duration > config.MAX_VOICE_DURATION_SECONDS:
        await update.message.reply_text(
            t("voice_too_long", minutes=config.MAX_VOICE_DURATION_SECONDS // 60)
        )
        return ReportState.COLLECTING_CONTENT.value
    
    voice = update.message.voice
    file = await context.bot.get_file(voice.file_id)
    voice_path = config.TEMP_DIR / f"{user_id}_{voice.file_unique_id}.ogg"
    await file.download_to_drive(voice_path)
    
    await update.message.reply_text(t("transcribing"))
    
    try:
        transcription = await voice_transcriber.transcribe(str(voice_path))
        session.add_voice_note(transcription)
        user_stats.increment(user_id, "voice_notes_added")
        
        keyboard = [[InlineKeyboardButton(t("btn_create_report"), callback_data="create_report")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        preview = transcription[:100] + "..." if len(transcription) > 100 else transcription
        
        await update.message.reply_text(
            t("transcribed", preview=preview),
            reply_markup=reply_markup,
        )
    except Exception as e:
        logger.error(f"Transcription error: {e}")
        await update.message.reply_text(t("transcription_error"))
    finally:
        voice_path.unlink(missing_ok=True)
    
    return ReportState.COLLECTING_CONTENT.value


async def handle_text_in_report(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle text during report collection."""
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    if not session:
        await update.message.reply_text(t("no_active_report"))
        return ConversationHandler.END
    
    session.add_text_note(update.message.text)
    user_stats.increment(user_id, "text_notes_added")
    
    keyboard = [[InlineKeyboardButton(t("btn_create_report"), callback_data="create_report")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("note_added"),
        reply_markup=reply_markup,
    )
    
    return ReportState.COLLECTING_CONTENT.value


# ============================================================================
# Report Generation
# ============================================================================

async def create_report_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Generate the final report."""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    if not session or session.is_empty():
        await query.edit_message_text(t("report_no_content"))
        return ConversationHandler.END
    
    await query.edit_message_text(t("creating_report"))
    
    try:
        profile = profile_manager.get_profile(user_id)
        participants = contacts_manager.get_contacts_by_ids(user_id, session.participant_ids)
        
        # Generate Word document
        doc_path = await word_generator.generate(session, profile, participants)
        user_stats.increment(user_id, "reports_created")
        
        # Clean up session
        session_manager.delete_session(user_id)
        
        # Send success message
        await query.edit_message_text(t("report_ready_word"))
        
        # Send the document file
        location = session.location or t("doc_site_inspection")
        with open(doc_path, "rb") as doc_file:
            await context.bot.send_document(
                chat_id=query.message.chat_id,
                document=doc_file,
                filename=os.path.basename(doc_path),
                caption=t("report_file_caption", location=location),
            )
        
        # Clean up the generated file after sending
        try:
            os.remove(doc_path)
        except Exception:
            pass
        
    except Exception as e:
        logger.error(f"Report generation error: {e}")
        await query.edit_message_text(t("report_error", error=str(e)))
    
    return ConversationHandler.END


async def cancel_report_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Cancel report."""
    query = update.callback_query
    await query.answer()
    
    user_id = update.effective_user.id
    session_manager.delete_session(user_id)
    context.user_data.pop("selected_participants", None)
    user_stats.increment(user_id, "reports_cancelled")
    
    await query.edit_message_text(t("report_cancelled"))
    return ConversationHandler.END


async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show current session status."""
    user_id = update.effective_user.id
    session = session_manager.get_session(user_id)
    
    if not session:
        await update.message.reply_text(t("no_active_report"))
        return
    
    status = session.get_content_summary()
    
    keyboard = [
        [InlineKeyboardButton(t("btn_create_report"), callback_data="create_report")],
        [InlineKeyboardButton(t("btn_cancel"), callback_data="cancel_report")],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        t("status_title") + "\n\n" + status,
        parse_mode="Markdown",
        reply_markup=reply_markup,
    )


async def cancel_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Cancel current report."""
    user_id = update.effective_user.id
    session_manager.delete_session(user_id)
    user_stats.increment(user_id, "reports_cancelled")
    await update.message.reply_text(t("report_cancelled"))
