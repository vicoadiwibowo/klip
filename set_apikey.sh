#!/data/data/com.termux/files/usr/bin/bash
# set_apikey.sh — Atur/ubah Gemini API key kapan saja tanpa install ulang
# Jalankan dengan: bash set_apikey.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
APIKEY_FILE="$CONFIG_DIR/apikey.env"
mkdir -p "$CONFIG_DIR"

CURRENT_KEY=""
if [ -f "$APIKEY_FILE" ]; then
  # shellcheck disable=SC1090
  source "$APIKEY_FILE"
  CURRENT_KEY="${GEMINI_API_KEY:-}"
fi

echo "Ambil Gemini API key gratis di: https://aistudio.google.com/app/apikey"
if [ -n "$CURRENT_KEY" ]; then
  echo "Key saat ini diakhiri: ...${CURRENT_KEY: -4}"
fi
read -r -p "Masukkan Gemini API key baru (kosongkan untuk batal): " NEW_KEY

if [ -z "$NEW_KEY" ]; then
  echo "Tidak ada perubahan."
  exit 0
fi

cat > "$APIKEY_FILE" <<EOF
# Dibuat otomatis — JANGAN diupload ke GitHub.
GEMINI_API_KEY="${NEW_KEY}"
EOF
chmod 600 "$APIKEY_FILE"
echo "API key berhasil disimpan."
echo "Jalankan aplikasi dengan: bash start.sh"
