<p align="center">
  <img src="docs/logo.png" alt="DocBot Logo" width="120">
</p>

<h1 align="center">DocBot</h1>

<p align="center">
  <strong>AI-Powered Inspection Reports via Telegram</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#demo">Demo</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#api-reference">API</a> •
  <a href="#deployment">Deployment</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/python-3.9+-blue.svg" alt="Python">
  <img src="https://img.shields.io/badge/telegram-bot-blue.svg" alt="Telegram">
  <img src="https://img.shields.io/badge/OpenAI-Whisper%20%7C%20GPT-green.svg" alt="OpenAI">
  <img src="https://img.shields.io/badge/Google-Docs%20API-yellow.svg" alt="Google">
  <img src="https://img.shields.io/badge/license-Proprietary-red.svg" alt="License">
</p>

---

## Overview

**DocBot** is a Telegram bot that transforms field inspections into professional reports. Inspectors can capture photos, record voice notes, and receive a fully formatted Google Doc — all from their phone.

```
📱 Field Inspector                    🤖 DocBot                         📄 Output
┌──────────────┐                ┌──────────────┐                 ┌──────────────┐
│ Take photos  │───────────────▶│ Transcribe   │────────────────▶│ Google Doc   │
│ Record voice │                │ Structure    │                 │ with photos  │
│ Add notes    │                │ Format       │                 │ Ready to edit│
└──────────────┘                └──────────────┘                 └──────────────┘
```

---

## Features

| Feature | Description |
|---------|-------------|
| 📷 **Photo Upload** | Send photos directly from your phone camera |
| 🎤 **Voice Notes** | Record observations - automatically transcribed via OpenAI Whisper |
| 📝 **Text Notes** | Add typed notes and comments |
| 🤖 **AI Structuring** | GPT organizes your notes into professional sections |
| 📄 **Google Docs** | Reports created in your own Google Drive |
| 👥 **Contacts** | Manage participants list for reports |
| 🏢 **Branding** | Add your company logo and details |
| 🔒 **Privacy** | Each user's data stays in their own Google account |
| 🌍 **Multi-language** | Supports any language (Hebrew, English, etc.) |

---

## Demo

<p align="center">
  <img src="docs/demo.gif" alt="DocBot Demo" width="300">
</p>

**First Time Setup (1 minute):**
```
Bot:  👋 Welcome! Let's set up your profile.
Bot:  Step 1: Send me your company logo
User: [Sends logo image]
Bot:  ✅ Logo saved!

Bot:  Step 2: What is your company name?
User: ABC Inspections Ltd.
Bot:  ✅ Company name saved!

Bot:  Step 3: Enter contact info
User: info@abc.com | 555-1234
Bot:  🎉 Setup Complete!
```

**Creating a Report:**
```
User: /new
Bot:  📝 New Report Started! (Company: ABC Inspections Ltd.)

User: [Sends photo of wall crack]
Bot:  📷 Photo 1 received!

User: [Voice message] "North wall has a 20cm crack, needs immediate repair"
Bot:  ✅ Voice transcribed: "North wall has a 20cm crack..."

User: [Presses "Create Report"]
Bot:  ✅ Report Created! [Open Report]
```

**Generated Report includes:**
- Your company logo
- Company name & contact info
- Professional formatting
- All photos with descriptions

---

## Quick Start

### Prerequisites

- Python 3.9+
- Telegram account
- OpenAI API account
- Google Cloud account

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/DocBot.git
cd DocBot

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Setup configuration
cp .env.example .env
# Edit .env with your API keys (see Configuration section)
```

### Configuration

Create a `.env` file with your credentials:

```env
TELEGRAM_BOT_TOKEN=your_telegram_token
OPENAI_API_KEY=your_openai_key
```

> ⚠️ **Security Note**: Never commit `.env` or `credentials.json` to version control!

### Run

```bash
python main.py
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              DocBot Architecture                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   📱 User's Phone                                                        │
│        │                                                                 │
│        ▼                                                                 │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐              │
│   │  Telegram   │────▶│   DocBot    │────▶│   OpenAI    │              │
│   │  Cloud      │◀────│   Server    │◀────│   API       │              │
│   └─────────────┘     └─────────────┘     └─────────────┘              │
│                              │                                          │
│                              ▼                                          │
│                       ┌─────────────┐                                   │
│                       │   Google    │                                   │
│                       │   Drive     │                                   │
│                       │   (User's)  │                                   │
│                       └─────────────┘                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Components

| Component | File | Description |
|-----------|------|-------------|
| **Bot Core** | `bot.py` | Telegram handlers, command processing |
| **Config** | `config.py` | Environment variables, settings |
| **Sessions** | `session_manager.py` | User report sessions (photos, notes) |
| **Transcription** | `voice_transcriber.py` | OpenAI Whisper integration |
| **Reports** | `report_generator.py` | GPT structuring + Google Docs creation |
| **Auth** | `google_auth.py` | OAuth2 flow for Google Drive |

---

## Project Structure

```
DocBot/
├── 📄 main.py                # Entry point
├── 📄 config.py              # Configuration
├── 📄 requirements.txt       # Dependencies
├── 📄 .env.example           # Environment template
│
├── 📁 bot/                   # Bot logic
│   ├── app.py                # Application setup
│   ├── states.py             # Conversation states
│   └── handlers/             # Command handlers
│       ├── start.py          # /start, /help
│       ├── report.py         # Report creation
│       ├── contacts.py       # Contact management
│       ├── setup.py          # User settings
│       └── google.py         # Google connection
│
├── 📁 services/              # Business logic
│   ├── voice_transcriber.py  # Whisper API
│   ├── report_generator.py   # GPT + Google Docs
│   └── google_auth.py        # OAuth2
│
├── 📁 data/                  # Data management
│   ├── session_manager.py    # Report sessions
│   ├── contacts_manager.py   # Contacts
│   └── user_profile.py       # User profiles
│
├── 📁 lang/                  # Languages
│   ├── he.py                 # Hebrew
│   └── en.py                 # English
│
└── 📁 docs/                  # Documentation
```

---

## API Keys Setup

### 1. Telegram Bot Token

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the prompts
3. Copy the token provided

### 2. OpenAI API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Navigate to API Keys
3. Create a new secret key

### 3. Google OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project
3. Enable **Google Docs API** and **Google Drive API**
4. Create OAuth 2.0 credentials (Desktop application)
5. Download JSON and save as `credentials.json`

---

## Security

### Secrets Management

| Secret | Storage | Git Status |
|--------|---------|------------|
| Telegram Token | `.env` file | ❌ Ignored |
| OpenAI Key | `.env` file | ❌ Ignored |
| Google Credentials | `credentials.json` | ❌ Ignored |
| User Tokens | `tokens/` folder | ❌ Ignored |

### OAuth Scopes

DocBot requests **minimal permissions**:

```python
GOOGLE_SCOPES = [
    "https://www.googleapis.com/auth/drive.file"  # Only files created by app
]
```

This means DocBot **cannot**:
- ❌ Read your existing files
- ❌ Access Gmail, Calendar, etc.
- ❌ Delete files it didn't create

---

## Deployment

### Local Development

```bash
python bot.py
```

### Production (Railway)

1. Push code to GitHub
2. Connect Railway to your repo
3. Add environment variables in Railway dashboard
4. Deploy!

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app)

### Docker

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "bot.py"]
```

---

## Cost Estimation

| Service | Cost | Notes |
|---------|------|-------|
| Telegram | Free | Unlimited messages |
| OpenAI Whisper | $0.006/min | ~$0.03 per 5-min voice |
| OpenAI GPT-4o-mini | ~$0.01/report | For structuring |
| Google APIs | Free | Within quota |
| **Total per report** | **~$0.05-0.10** | |

---

## Commands Reference

| Command | Description |
|---------|-------------|
| `/start` | Welcome message and instructions |
| `/new` | Start a new report |
| `/status` | Check current report progress |
| `/cancel` | Cancel current report |
| `/connect` | Connect Google Drive |
| `/disconnect` | Disconnect Google Drive |
| `/help` | Show help message |

---

## Contact

Interested in using DocBot for your organization? 

📧 Contact: [your-email@example.com]

I offer:
- 🏢 Commercial licenses
- 🛠️ Custom development
- 🎓 Training and support

---

## License

⚠️ **This project is NOT open source.**

This code is provided for **viewing and educational purposes only**. 

You may NOT use, copy, modify, or distribute this software without explicit written permission.

For licensing inquiries, please contact: [your-email@example.com]

See [LICENSE](LICENSE) for full terms.

---

## Acknowledgments

- [python-telegram-bot](https://github.com/python-telegram-bot/python-telegram-bot) - Telegram Bot API wrapper
- [OpenAI](https://openai.com) - Whisper & GPT APIs
- [Google APIs](https://developers.google.com) - Docs & Drive integration

---

<p align="center">
  Made with ❤️ for field inspectors everywhere
</p>
