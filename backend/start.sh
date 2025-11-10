#!/bin/bash
# Multi-process startup script for Railway
# Runs both Node.js server and Python agent

set -e

echo "🚀 Starting multi-process deployment..."

# Function to handle cleanup on exit
cleanup() {
    echo "🛑 Shutting down processes..."
    kill $(jobs -p) 2>/dev/null || true
    exit
}

trap cleanup SIGTERM SIGINT

# Start Python agent in background
echo "🤖 Starting LiveKit agent..."
python agent.py start &
AGENT_PID=$!

# Give agent a moment to initialize
sleep 2

# Check if agent is still running
if ! kill -0 $AGENT_PID 2>/dev/null; then
    echo "❌ Agent failed to start!"
    exit 1
fi

echo "✅ Agent started (PID: $AGENT_PID)"

# Start Node.js server in foreground (Railway needs one foreground process)
echo "🌐 Starting Node.js server..."
npm start &
SERVER_PID=$!

echo "✅ Server started (PID: $SERVER_PID)"

# Wait for both processes
wait -n

# If either process exits, kill the other and exit
echo "⚠️  One process exited, shutting down..."
cleanup
