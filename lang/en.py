"""
English language strings for DocBot
===================================
"""

STRINGS = {
    # Welcome & Help
    "welcome_message": """
Hello! 👋

I help you create inspection reports quickly.

**How it works:**
1. Send /new to start a report
2. Take photos and send them
3. Record voice notes
4. Press "Create Report" → Document ready!

**Commands:**
/new - New report
/contacts - Manage contacts
/help - Help

""",
    
    "help_message": """
📖 **Help**

**Creating a Report:**
/new → Select location → Select participants → Send photos & recordings → Create report

**Tips:**
• Speak clearly when recording
• Describe what you see in each photo
• You can send multiple photos and recordings

**Commands:**
/new - Start new report
/status - Current report status
/cancel - Cancel report
/contacts - Manage contacts
/mylogo - My logo
/setup - Change settings

**Problem?** Send a message and I'll help.
""",
    
    # Buttons
    "btn_connect_google": "🔗 Connect Google Drive",
    "btn_start_report": "📝 Start New Report",
    "btn_skip": "⏭️ Skip",
    "btn_add_contact": "➕ Add Contact",
    "btn_add_new": "➕ Add New",
    "btn_continue_no_participants": "⏭️ Continue Without Participants",
    "btn_done_selection": "✅ Done",
    "btn_create_report": "✅ Create Report",
    "btn_cancel": "❌ Cancel",
    "btn_open_report": "📄 Open Report",
    "btn_delete": "🗑️ Delete",
    "btn_connect": "🔗 Connect",
    
    # Report Flow
    "new_report_title": "📝 **New Report**",
    "ask_location": "📍 Where is the inspection?\n_(Example: Hadera East Station)_",
    "ask_location_with_choices": "📍 Where is the inspection?\nChoose from the list or send a new location.",
    "location_not_specified": "📍 Location: Not specified",
    "location_selected": "📍 Location: {location}",
    "select_participants_title": "👥 **Select Participants**",
    "select_participants_count": "👥 **Select Participants** ({count} selected)",
    "select_participants_instruction": "Tap a name to select/deselect:",
    "no_contacts_yet": "No contacts yet.\nYou can add now or continue.",
    "participants_selected": "👥 Participants: {names}",
    "participants_not_specified": "👥 Participants: Not specified",
    
    "content_instructions": """📷 **Now send content:**

• Photos from the site
• Voice recordings
• Or text messages

When done - press "Create Report\"""",
    
    "photo_received": "📷 Photo {count} received!\n\nSend more photos/recordings, or create report.",
    "transcribing": "🎤 Transcribing...",
    "transcribed": "✅ Transcribed:\n\n\"{preview}\"",
    "transcription_error": "❌ Transcription error. Try again or send text.",
    "voice_too_long": "⚠️ Recording too long (max {minutes} minutes).",
    "note_added": "📝 Note added!",
    
    "creating_report": "⏳ Creating report... Please wait.",
    "report_ready": "✅ **Report Ready!**\n\nClick to open. You can download as Word or PDF.",
    "report_ready_word": "✅ **Report Ready!**",
    "report_file_caption": "📄 Inspection Report - {location}",
    "report_error": "❌ Error: {error}",
    "report_no_content": "❌ No content for report. Add photos or recordings.",
    "report_cancelled": "🗑️ Report cancelled.",
    
    "no_active_report": "No active report. Send /new to start.",
    "need_google_connection": "⚠️ You need to connect Google Drive first!",
    "important_connect_google": "\n⚠️ **Important:** Connect Google Drive to create reports.",
    
    # Contacts
    "contacts_title": "📇 **Contacts:**",
    "contacts_empty": "📇 **Contacts**\n\nNo contacts yet.",
    "add_contact_title": "👤 **Add Contact**",
    "ask_name": "What is the name?",
    "ask_name_or_share": "What is the name?\nOr share a contact via Telegram attachment (📎 → Contact).",
    "ask_email": "What is the email?",
    "ask_organization": "What is the organization? (e.g., Israel Railways)",
    "name_saved": "✅ Name: {name}",
    "email_saved": "✅ Email: {email}",
    "email_skipped": "⏭️ Email: Not specified",
    "contact_added": "✅ **Contact Added!**\n\n{name}",
    "contact_unknown_name": "Contact",
    "returning_to_selection": "\n\nReturning to participant selection...",
    "cancelled": "❌ Cancelled.",
    "contact_share_not_supported": "That button only shares your own info. To choose another contact, use 📎 → Contact.",
    
    # Setup
    "setup_title": "⚙️ **Settings**",
    "setup_ask_logo": "📷 Send your company logo:",
    "setup_logo_saved": "✅ Logo saved!",
    "setup_logo_skipped": "⏭️ Logo: Not set",
    "setup_ask_company": "What is the company name?",
    "setup_company_saved": "✅ Company name: {name}",
    "setup_company_skipped": "⏭️ Company name: Not set",
    "setup_ask_contact": "Contact info? (phone, email)",
    "setup_complete": "✅ **Settings Saved!**\n\nSend /new to create a report.",
    "setup_send_image": "Send an image or press skip.",
    
    # Google Connection
    "google_already_connected": "✅ Google Drive already connected!\n\nTo disconnect: /disconnect",
    "google_connect_title": "🔐 **Connect Google Drive**",
    "google_connect_instruction": "Click to connect.\n\n⚠️ The bot can only access files it creates.",
    "google_disconnected": "✅ Google Drive disconnected.",
    "google_not_connected": "Not connected to Google Drive.",
    
    # Status
    "status_title": "📊 **Report Status:**",
    
    # Logo
    "logo_current": "Your logo. To change: /setup",
    "logo_none": "No logo. To add: /setup",
    
    # General
    "send_connect": "Send /connect to connect to Google Drive.",
    "send_new": "Send /new to start a report.",
    
    # Report Document
    "doc_date": "Date",
    "doc_location": "Location",
    "doc_participants": "Participants",
    "doc_summary": "Summary",
    "doc_findings": "Findings",
    "doc_finding": "Finding",
    "doc_recommendations": "Recommendations",
    "doc_photos": "Photos",
    "doc_photo": "Photo",
    "doc_page": "Page",
    "doc_inspection_report": "Inspection Report",
    "doc_site_inspection": "Site Inspection",
    "doc_generated_by_docbot": "Generated by DocBot",
    "doc_photo_error": "Could not load",
}
