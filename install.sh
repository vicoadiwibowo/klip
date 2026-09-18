#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — Auto Installer "AI Video Klip" untuk Termux
# Jalankan dengan:
#   bash install.sh
#
set -uo pipefail

C_RESET="\033[0m"; C_RED="\033[1;31m"; C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"; C_BLUE="\033[1;34m"

info(){ echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
ok(){   echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
warn(){ echo -e "${C_YELLOW}[PERINGATAN]${C_RESET} $1"; }
err(){  echo -e "${C_RED}[GAGAL]${C_RESET} $1"; }

fail_exit(){
  err "$1"
  echo
  echo "Instalasi dihentikan. Perbaiki masalah di atas, lalu jalankan ulang:"
  echo "  bash install.sh"
  exit 1
}

# ---------- 0. Pastikan berjalan di Termux ----------
if [ -z "${PREFIX:-}" ] || ! command -v pkg >/dev/null 2>&1; then
  fail_exit "Script ini hanya bisa dijalankan di dalam aplikasi Termux."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || fail_exit "Tidak bisa masuk ke folder proyek: $SCRIPT_DIR"

echo "=================================================="
echo "   AI VIDEO KLIP — AUTO INSTALLER UNTUK TERMUX"
echo "=================================================="
echo "Lokasi proyek: $SCRIPT_DIR"
echo

retry(){
  local n=1 max=3 delay=5
  until "$@"; do
    if [ $n -ge $max ]; then return 1; fi
    warn "Percobaan $n gagal, mencoba lagi dalam ${delay}s..."
    n=$((n+1)); sleep $delay
  done
  return 0
}

# ---------- 1. Update daftar paket (sekaligus tes koneksi internet) ----------
info "Memperbarui daftar paket Termux (butuh internet)..."
export DEBIAN_FRONTEND=noninteractive
if ! retry pkg update -y; then
  fail_exit "Gagal 'pkg update'. Pastikan WiFi/data internet aktif, lalu jalankan ulang script ini."
fi
ok "Daftar paket berhasil diperbarui."

info "Meng-upgrade paket Termux yang sudah terpasang..."
retry pkg upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  || warn "Sebagian paket gagal di-upgrade, instalasi tetap dilanjutkan."

# ---------- 2. Install paket sistem ----------
CORE_PKGS=(python git ffmpeg clang make pkg-config libffi openssl)
for p in "${CORE_PKGS[@]}"; do
  info "Menginstall paket: $p ..."
  if retry pkg install -y "$p"; then
    ok "$p terpasang."
  else
    case "$p" in
      python|ffmpeg)
        fail_exit "Paket wajib '$p' gagal terpasang. Coba manual: pkg install $p" ;;
      *)
        warn "Paket opsional '$p' gagal terpasang, dilanjutkan." ;;
    esac
  fi
done

PYTHON_BIN="python"
if ! command -v python >/dev/null 2>&1; then
  command -v python3 >/dev/null 2>&1 && PYTHON_BIN="python3" \
    || fail_exit "Python tidak ditemukan setelah instalasi."
fi
command -v "$PYTHON_BIN" -m pip --version >/dev/null 2>&1 || retry pkg install -y python-pip || true

# ---------- 3. Install yt-dlp (utamakan pkg, fallback pip) ----------
info "Menginstall yt-dlp..."
if retry pkg install -y yt-dlp; then
  ok "yt-dlp terpasang lewat pkg."
else
  warn "yt-dlp tidak tersedia lewat pkg, mencoba lewat pip..."
  if ! retry "$PYTHON_BIN" -m pip install --upgrade yt-dlp; then
    fail_exit "Gagal menginstall yt-dlp. Coba manual: pip install yt-dlp"
  fi
  ok "yt-dlp terpasang lewat pip."
fi

# ---------- 4. Siapkan pip & dependency Python ----------
info "Memperbarui pip, setuptools, wheel..."
retry "$PYTHON_BIN" -m pip install --upgrade pip setuptools wheel \
  || fail_exit "Gagal memperbarui pip."
ok "pip siap."

if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
  info "Menginstall dependency dari requirements.txt..."
  retry "$PYTHON_BIN" -m pip install -r "$SCRIPT_DIR/requirements.txt" \
    || fail_exit "Gagal menginstall dependency Python dari requirements.txt."
else
  info "Menginstall dependency Python (flask, requests)..."
  retry "$PYTHON_BIN" -m pip install flask requests \
    || fail_exit "Gagal menginstall flask/requests."
fi
ok "Dependency Python terpasang."

# ---------- 5. Verifikasi semua komponen ----------
info "Memverifikasi instalasi..."
"$PYTHON_BIN" -c "import flask, requests" 2>/dev/null \
  || fail_exit "Modul flask/requests gagal di-import."
command -v ffmpeg  >/dev/null 2>&1 || fail_exit "ffmpeg tidak ditemukan."
command -v ffprobe >/dev/null 2>&1 || fail_exit "ffprobe tidak ditemukan."
command -v yt-dlp  >/dev/null 2>&1 || fail_exit "yt-dlp tidak ditemukan."
ok "Semua komponen terverifikasi: python, flask, requests, ffmpeg, ffprobe, yt-dlp."

# ---------- 6. Siapkan folder proyek ----------
mkdir -p "$SCRIPT_DIR"/downloads "$SCRIPT_DIR"/clips \
         "$SCRIPT_DIR"/uploads_srt "$SCRIPT_DIR"/uploads_music \
         "$SCRIPT_DIR"/config

if [ ! -f "$SCRIPT_DIR/templates/index.html" ]; then
  warn "templates/index.html tidak ditemukan."
  warn "Pastikan folder 'templates' (dan 'static' jika ada) ikut ter-clone dari GitHub."
fi

echo
echo "=================================================="
ok "SEMUA KOMPONEN BERHASIL DIINSTALL"
echo "=================================================="
echo

# ---------- 7. Baru sekarang minta Gemini API key ----------
APIKEY_FILE="$SCRIPT_DIR/config/apikey.env"
CURRENT_KEY=""
if [ -f "$APIKEY_FILE" ]; then
  # shellcheck disable=SC1090
  source "$APIKEY_FILE"
  CURRENT_KEY="${GEMINI_API_KEY:-}"
fi

echo "Langkah terakhir: masukkan Gemini API key kamu."
echo "Ambil gratis di: https://aistudio.google.com/app/apikey"
if [ -n "$CURRENT_KEY" ]; then
  echo "API key lama sudah tersimpan (akhiran: ...${CURRENT_KEY: -4})."
  echo "Kosongkan lalu Enter untuk tetap memakai key lama."
fi
echo
read -r -p "Masukkan Gemini API key: " INPUT_KEY

if [ -z "$INPUT_KEY" ] && [ -n "$CURRENT_KEY" ]; then
  INPUT_KEY="$CURRENT_KEY"
  info "Memakai API key yang sudah ada."
elif [ -z "$INPUT_KEY" ]; then
  warn "Dikosongkan. Fitur analisis Gemini belum aktif sampai kamu mengisi key."
  warn "Isi kapan saja dengan: bash set_apikey.sh"
fi

cat > "$APIKEY_FILE" <<EOF
# Dibuat otomatis oleh install.sh — JANGAN diupload ke GitHub.
GEMINI_API_KEY="${INPUT_KEY}"
EOF
chmod 600 "$APIKEY_FILE"
ok "API key tersimpan di config/apikey.env"

echo
echo "=================================================="
ok "INSTALASI SELESAI"
echo "=================================================="
echo "Cara menjalankan aplikasi kapan pun:"
echo "  bash start.sh"
echo
echo "Lalu buka di browser HP:"
echo "  http://127.0.0.1:5000"
echo
read -r -p "Jalankan aplikasi sekarang? (Y/n): " RUN_NOW
RUN_NOW="${RUN_NOW:-Y}"
if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
  bash "$SCRIPT_DIR/start.sh"
fi
