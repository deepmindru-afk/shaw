#!/bin/bash
# Local testing script for agent + server

set -e

echo "🧪 Local Test Environment"
echo "========================="

# Check .env file
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    exit 1
fi

echo "✅ Found .env file"

# Load environment variables
source .env

# Check required vars
if [ -z "$LIVEKIT_API_KEY" ] || [ -z "$LIVEKIT_API_SECRET" ] || [ -z "$LIVEKIT_URL" ]; then
    echo "❌ Missing LiveKit configuration in .env"
    echo "   Required: LIVEKIT_API_KEY, LIVEKIT_API_SECRET, LIVEKIT_URL"
    exit 1
fi

echo "✅ LiveKit configuration found"
echo "   URL: $LIVEKIT_URL"
echo "   API Key: ${LIVEKIT_API_KEY:0:10}..."

# Check OpenAI API key for agent
if [ -z "$OPENAI_API_KEY" ]; then
    echo "⚠️  Warning: OPENAI_API_KEY not set (agent will fail)"
fi

# Check virtual environment
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found. Run: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

echo "✅ Virtual environment found"

# Start server in background
echo ""
echo "🌐 Starting Node.js server..."
npm start &
SERVER_PID=$!
sleep 3

# Test server health
if curl -s http://localhost:3000/health > /dev/null; then
    echo "✅ Server is running (PID: $SERVER_PID)"
else
    echo "❌ Server failed to start"
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi

# Start agent
echo ""
echo "🤖 Starting LiveKit agent..."
echo "   Press Ctrl+C to stop both server and agent"
echo ""

# Activate venv and run agent
source venv/bin/activate
python agent.py start

# Cleanup on exit
kill $SERVER_PID 2>/dev/null || true
