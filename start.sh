#!/data/data/com.termux/files/usr/bin/bash
# start.sh — Menjalankan AI Video Klip
# Jalankan dengan: bash start.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

APIKEY_FILE="$SCRIPT_DIR/config/apikey.env"
if [ -f "$APIKEY_FILE" ]; then
  # shellcheck disable=SC1090
  source "$APIKEY_FILE"
  export GEMINI_API_KEY
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "[PERINGATAN] Gemini API key belum diatur."
  echo "Jalankan dulu: bash set_apikey.sh"
  echo
fi

PYTHON_BIN="python"
command -v python >/dev/null 2>&1 || PYTHON_BIN="python3"

echo "=================================================="
echo " Menjalankan AI Video Klip..."
echo " Buka di browser HP: http://127.0.0.1:5000"
echo " (Tekan CTRL+C untuk berhenti)"
echo "=================================================="
echo

exec "$PYTHON_BIN" "$SCRIPT_DIR/app.py"
