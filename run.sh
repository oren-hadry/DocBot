#!/bin/bash

# DocBot Runner Script
# ====================

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🤖 DocBot Runner${NC}"
echo "=================="

# Check for .env file
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ Missing .env file!${NC}"
    echo ""
    echo "Create .env with:"
    echo "  TELEGRAM_BOT_TOKEN=your_token"
    echo "  OPENAI_API_KEY=your_key"
    echo ""
    echo "Or copy from example:"
    echo "  cp .env.example .env"
    exit 1
fi

# Check/create virtual environment
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}📦 Creating virtual environment...${NC}"
    python3 -m venv venv
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to create venv${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Virtual environment created${NC}"
fi

# Activate virtual environment
echo -e "${YELLOW}🔄 Activating virtual environment...${NC}"
source venv/bin/activate

# Check/install dependencies
if [ ! -f "venv/.deps_installed" ] || [ "requirements.txt" -nt "venv/.deps_installed" ]; then
    echo -e "${YELLOW}📥 Installing dependencies...${NC}"
    pip install -q -r requirements.txt
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to install dependencies${NC}"
        exit 1
    fi
    touch venv/.deps_installed
    echo -e "${GREEN}✅ Dependencies installed${NC}"
fi

# Run the bot
echo ""
echo -e "${GREEN}🚀 Starting DocBot...${NC}"
echo "Press Ctrl+C to stop"
echo ""

python main.py
