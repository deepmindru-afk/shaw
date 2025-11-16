#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="${VENV_DIR:-.venv}"
if [ ! -d "$VENV_DIR" ]; then
  echo "📦 Creating Python virtualenv in $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip >/dev/null
python -m pip install -r requirements.txt >/dev/null

echo "🚀 Starting web server and agent worker..."
"$VENV_DIR/bin/python" agent.py &
AGENT_PID=$!
trap 'kill $AGENT_PID 2>/dev/null || true' EXIT

echo "✅ Agent worker started (PID: $AGENT_PID)"

echo "✅ Starting web server..."
npm start
