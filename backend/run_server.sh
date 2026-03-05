#!/bin/bash
# Запуск бэкенда на сервере (Ubuntu, headless).
# Использование:
#   chmod +x run_server.sh
#   ./run_server.sh          # Vertex-only (app_vertex)
#   ./run_server.sh main     # Полный бэкенд (main.py, Supabase + Gemini/API key)

set -e
cd "$(dirname "$0")"

APP="${1:-app_vertex}"
PORT="${PORT:-8000}"
HOST="${HOST:-0.0.0.0}"

if [ -d "$HOME/myenv/bin" ]; then
  source "$HOME/myenv/bin/activate"
elif [ -d ".venv/bin" ]; then
  source .venv/bin/activate
fi

echo "Starting $APP on $HOST:$PORT (Ctrl+C to stop)"
exec python3 -m uvicorn "${APP}:app" --host "$HOST" --port "$PORT"
