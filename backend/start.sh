#!/bin/bash

AGENT_LOG_FILE="/tmp/agent.log"
SERVER_PID=""
AGENT_SUPERVISOR_PID=""

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  echo "🛑 Shutdown signal received. Stopping services..."
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "$AGENT_SUPERVISOR_PID" ]] && kill -0 "$AGENT_SUPERVISOR_PID" 2>/dev/null; then
    kill "$AGENT_SUPERVISOR_PID" 2>/dev/null || true
  fi
  wait "$AGENT_SUPERVISOR_PID" 2>/dev/null || true
  exit 0
}
trap cleanup TERM INT

# Set up library paths for LiveKit Python SDK
# Nixpacks installs libraries in various locations, we need to find them

echo "🔍 Locating C++ standard library..."

# Find libstdc++.so.6 in common locations
FOUND_LIB=""

# Check /root/.nix-profile/lib first (most common in Nixpacks)
if [ -f "/root/.nix-profile/lib/libstdc++.so.6" ]; then
  FOUND_LIB="/root/.nix-profile/lib"
  echo "✅ Found libstdc++.so.6 at: $FOUND_LIB"
fi

# Search recursively in /nix/store if not found
if [ -z "$FOUND_LIB" ]; then
  echo "🔍 Searching /nix/store recursively..."
  FOUND_LIB=$(find /nix/store -name "libstdc++.so.6" -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
  if [ -n "$FOUND_LIB" ]; then
    echo "✅ Found libstdc++.so.6 at: $FOUND_LIB"
  fi
fi

# Check standard system locations as fallback
if [ -z "$FOUND_LIB" ]; then
  for path in "/usr/lib" "/usr/lib/x86_64-linux-gnu"; do
    if [ -f "$path/libstdc++.so.6" ]; then
      FOUND_LIB="$path"
      echo "✅ Found libstdc++.so.6 at: $FOUND_LIB"
      break
    fi
  done
fi

# Set LD_LIBRARY_PATH
if [ -n "$FOUND_LIB" ]; then
  export LD_LIBRARY_PATH="$FOUND_LIB:${LD_LIBRARY_PATH:-}"
  echo "✅ LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
else
  echo "⚠️  Warning: libstdc++.so.6 not found, using default library paths"
  echo "   LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-<not set>}"
fi

# Find Python executable (works with both Nixpacks and Metal)
PYTHON_CMD=""
if [ -f "/opt/venv/bin/python" ]; then
  PYTHON_CMD="/opt/venv/bin/python"
elif [ -f "backend/venv/bin/python" ]; then
  PYTHON_CMD="backend/venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD=$(command -v python3)
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD=$(command -v python)
else
  echo "❌ Python not found! Available commands:"
  which -a python3 python 2>/dev/null || echo "  No python found"
  exit 1
fi

echo "🔍 Using Python: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1 || echo 'version check failed'))"

# Verify Python can find the library (non-fatal, for debugging)
echo "🔍 Verifying Python library dependencies..."
$PYTHON_CMD -c "
import sys
import os
print(f'Python: {sys.executable}')
print(f'LD_LIBRARY_PATH: {os.environ.get(\"LD_LIBRARY_PATH\", \"<not set>\")}')
try:
    import livekit
    print('✅ LiveKit Python SDK imported successfully')
except Exception as e:
    print(f'⚠️  Warning: Failed to import LiveKit: {e}')
    print('   This may cause the agent worker to fail. Continuing anyway...')
" || echo "⚠️  Python library check had issues, but continuing..."

# Start both the web server and agent worker (unless disabled)
echo "🚀 Starting web server and agent worker..."

# Verify LiveKit environment variables are set (both backend and agent need them)
echo "🔍 Verifying LiveKit environment variables..."
if [ -z "$LIVEKIT_URL" ] || [ -z "$LIVEKIT_API_KEY" ] || [ -z "$LIVEKIT_API_SECRET" ]; then
  echo "❌ ERROR: LiveKit environment variables are not set!"
  echo "   Required: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET"
  echo "   Please set these in Railway dashboard or .env file"
  exit 1
fi
echo "✅ LiveKit environment variables are set"

cd "$(dirname "$0")" || exit 1  # Ensure we're in the backend directory

# If we only want the web server (no embedded agent), start it and exit
if is_true "${DISABLE_EMBEDDED_AGENT:-}"; then
  echo "ℹ️ Embedded agent disabled (DISABLE_EMBEDDED_AGENT=${DISABLE_EMBEDDED_AGENT}). Starting web server only..."
  echo "✅ Starting web server..."
  npm start &
  SERVER_PID=$!
  wait $SERVER_PID
  SERVER_EXIT=$?
  echo "❌ Web server exited with code $SERVER_EXIT"
  exit $SERVER_EXIT
fi

: > "$AGENT_LOG_FILE"
echo "🧹 Cleared agent log: $AGENT_LOG_FILE"

start_agent_supervisor() {
  local attempt=1
  local child_pid=0
  trap 'if [[ $child_pid -ne 0 ]]; then echo "🛑 Stopping agent worker (PID: $child_pid)"; kill $child_pid 2>/dev/null; wait $child_pid 2>/dev/null; fi; exit 0' TERM INT
  while true; do
    echo "🚀 Starting agent worker (attempt $attempt)..."
    "$PYTHON_CMD" agent.py start \
      > >(tee -a "$AGENT_LOG_FILE") \
      2> >(tee -a "$AGENT_LOG_FILE" >&2) &
    child_pid=$!
    wait $child_pid
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      echo "⚠️  Agent worker exited with code $exit_code. Restarting in 2s..."
      echo "   Check $AGENT_LOG_FILE for details."
    else
      echo "ℹ️  Agent worker exited cleanly. Restarting to ensure availability..."
    fi
    sleep 2
    attempt=$((attempt + 1))
  done
}

# Start agent supervisor in background to auto-restart the worker
start_agent_supervisor &
AGENT_SUPERVISOR_PID=$!
echo "✅ Agent supervisor started (PID: $AGENT_SUPERVISOR_PID)"
echo "   Logs: $AGENT_LOG_FILE (also streaming to stdout)"

# Wait for the first agent worker instance to come up
echo "⏳ Waiting for agent worker to connect to LiveKit Cloud..."
agent_ready=0
for _ in {1..15}; do
  if pgrep -f "agent.py start" >/dev/null; then
    agent_ready=1
    break
  fi
  sleep 1
done

if [[ $agent_ready -eq 1 ]]; then
  if grep -q "Connecting to LiveKit Cloud\|agent worker\|Agent name" "$AGENT_LOG_FILE" 2>/dev/null; then
    echo "✅ Agent worker logs show connection activity"
  else
    echo "⚠️  Agent worker running but connection logs not detected yet"
    tail -10 "$AGENT_LOG_FILE" 2>/dev/null || true
  fi
else
  echo "❌ Agent worker failed to start. Last 30 lines of agent.log:"
  tail -30 "$AGENT_LOG_FILE" 2>/dev/null || echo "   (log file not found)"
  kill "$AGENT_SUPERVISOR_PID" 2>/dev/null || true
  wait "$AGENT_SUPERVISOR_PID" 2>/dev/null || true
  exit 1
fi

echo "✅ Agent worker supervisor is running"
echo "   Monitor logs with: tail -f $AGENT_LOG_FILE"

# Start web server in foreground while supervisor keeps agent healthy
echo "✅ Starting web server..."
npm start &
SERVER_PID=$!
wait $SERVER_PID
SERVER_EXIT=$?
echo "❌ Web server exited with code $SERVER_EXIT"

# Stop supervisor on exit to keep process tidy
if [[ -n "$AGENT_SUPERVISOR_PID" ]] && kill -0 "$AGENT_SUPERVISOR_PID" 2>/dev/null; then
  kill "$AGENT_SUPERVISOR_PID" 2>/dev/null || true
  wait "$AGENT_SUPERVISOR_PID" 2>/dev/null || true
fi

exit $SERVER_EXIT
