#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — Auto Installer "AI Video Klip" untuk Termux
#
# Cara pakai (pilih salah satu):
#   1) Sudah clone repo sendiri:
#        cd klip && bash install.sh
#   2) One-liner tanpa clone manual (installer akan clone sendiri):
#        curl -sL https://raw.githubusercontent.com/vicoadiwibowo/klip/main/install.sh | bash
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
  echo "Instalasi dihentikan. Perbaiki masalah di atas, lalu jalankan ulang perintah installer-nya."
  exit 1
}

# read yang selalu ambil input dari keyboard asli (/dev/tty), bukan dari
# stdin — penting karena saat dijalankan lewat "curl ... | bash", stdin
# terisi oleh output curl, bukan oleh keyboard pengguna.
ask(){
  local prompt="$1" __var="$2" val=""
  if [ -r /dev/tty ]; then
    read -r -p "$prompt" val < /dev/tty || true
  else
    read -r -p "$prompt" val || true
  fi
  printf -v "$__var" '%s' "$val"
}

retry(){
  local n=1 max=3 delay=5
  until "$@"; do
    if [ $n -ge $max ]; then return 1; fi
    warn "Percobaan $n gagal, mencoba lagi dalam ${delay}s..."
    n=$((n+1)); sleep $delay
  done
  return 0
}

# ---------- 0. Pastikan berjalan di Termux ----------
if [ -z "${PREFIX:-}" ] || ! command -v pkg >/dev/null 2>&1; then
  fail_exit "Script ini hanya bisa dijalankan di dalam aplikasi Termux."
fi

echo "=================================================="
echo "   AI VIDEO KLIP — AUTO INSTALLER UNTUK TERMUX"
echo "=================================================="
echo

# ---------- 1. Update daftar paket (sekaligus tes koneksi internet) ----------
info "Memperbarui daftar paket Termux (butuh internet)..."
export DEBIAN_FRONTEND=noninteractive
if ! retry pkg update -y; then
  fail_exit "Gagal 'pkg update'. Pastikan WiFi/data internet aktif, lalu jalankan ulang."
fi
ok "Daftar paket berhasil diperbarui."

# ---------- 2. Pastikan git tersedia (dibutuhkan untuk clone/update repo) ----------
if ! command -v git >/dev/null 2>&1; then
  info "Menginstall git..."
  retry pkg install -y git || fail_exit "Gagal menginstall git."
fi
ok "git siap."

# ---------- 3. Tentukan folder proyek: pakai yang sudah ada, atau clone sendiri ----------
REPO_URL="${REPO_URL:-https://github.com/vicoadiwibowo/klip.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/klip}"

SCRIPT_FILE=""
if [ -n "${BASH_SOURCE:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_FILE" ] && [ -f "$SCRIPT_FILE/app.py" ]; then
  # Dijalankan langsung dari dalam repo yang sudah di-clone/download.
  SCRIPT_DIR="$SCRIPT_FILE"
  info "Memakai folder proyek yang sudah ada: $SCRIPT_DIR"
else
  # Dijalankan lewat curl | bash — tidak ada file lokal, clone repo dulu.
  info "Mode instalasi langsung (curl | bash) terdeteksi."
  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Folder $INSTALL_DIR sudah ada, menarik update terbaru..."
    retry git -C "$INSTALL_DIR" pull --ff-only \
      || warn "Gagal menarik update terbaru, memakai isi folder yang ada."
  elif [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    warn "Folder $INSTALL_DIR sudah ada isinya tapi bukan hasil git clone."
    ask "Hapus isi lama & clone ulang ke folder itu? (y/N): " CONFIRM_WIPE
    if [[ "$CONFIRM_WIPE" =~ ^[Yy]$ ]]; then
      rm -rf "$INSTALL_DIR"
      retry git clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" \
        || fail_exit "Gagal clone repo. Cek URL repo/koneksi internet."
    else
      fail_exit "Dibatalkan. Hapus folder $INSTALL_DIR secara manual, atau jalankan ulang dengan: INSTALL_DIR=\$HOME/nama-lain bash install.sh"
    fi
  else
    info "Meng-clone proyek ke $INSTALL_DIR ..."
    retry git clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" \
      || fail_exit "Gagal clone repo. Cek URL repo/koneksi internet."
  fi
  SCRIPT_DIR="$INSTALL_DIR"
fi

cd "$SCRIPT_DIR" || fail_exit "Tidak bisa masuk ke folder proyek: $SCRIPT_DIR"
ok "Lokasi proyek: $SCRIPT_DIR"
echo

# ---------- 4. Upgrade paket Termux yang sudah terpasang ----------
info "Meng-upgrade paket Termux yang sudah terpasang..."
retry pkg upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  || warn "Sebagian paket gagal di-upgrade, instalasi tetap dilanjutkan."

# ---------- 5. Install paket sistem lain ----------
CORE_PKGS=(python ffmpeg clang make pkg-config libffi openssl)
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
"$PYTHON_BIN" -m pip --version >/dev/null 2>&1 || retry pkg install -y python-pip || true

# ---------- 6. Install yt-dlp (utamakan pkg, fallback pip) ----------
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

# ---------- 7. Siapkan pip & dependency Python ----------
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

# ---------- 8. Verifikasi semua komponen ----------
info "Memverifikasi instalasi..."
"$PYTHON_BIN" -c "import flask, requests" 2>/dev/null \
  || fail_exit "Modul flask/requests gagal di-import."
command -v ffmpeg  >/dev/null 2>&1 || fail_exit "ffmpeg tidak ditemukan."
command -v ffprobe >/dev/null 2>&1 || fail_exit "ffprobe tidak ditemukan."
command -v yt-dlp  >/dev/null 2>&1 || fail_exit "yt-dlp tidak ditemukan."
[ -f "$SCRIPT_DIR/app.py" ] || fail_exit "app.py tidak ditemukan di $SCRIPT_DIR."
ok "Semua komponen terverifikasi: python, flask, requests, ffmpeg, ffprobe, yt-dlp, app.py."

# ---------- 9. Siapkan folder proyek ----------
mkdir -p "$SCRIPT_DIR"/downloads "$SCRIPT_DIR"/clips \
         "$SCRIPT_DIR"/uploads_srt "$SCRIPT_DIR"/uploads_music \
         "$SCRIPT_DIR"/config

if [ ! -f "$SCRIPT_DIR/templates/index.html" ]; then
  warn "templates/index.html tidak ditemukan."
  warn "Pastikan folder 'templates' (dan 'static' jika ada) ada di repo GitHub kamu."
fi

echo
echo "=================================================="
ok "SEMUA KOMPONEN BERHASIL DIINSTALL"
echo "=================================================="
echo

# ---------- 10. Baru sekarang minta Gemini API key ----------
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
ask "Masukkan Gemini API key: " INPUT_KEY

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
echo "Folder proyek: $SCRIPT_DIR"
echo
echo "Cara menjalankan aplikasi kapan pun:"
echo "  cd $SCRIPT_DIR && bash start.sh"
echo
echo "Lalu buka di browser HP:"
echo "  http://127.0.0.1:5000"
echo

if [ -f "$SCRIPT_DIR/start.sh" ]; then
  ask "Jalankan aplikasi sekarang? (Y/n): " RUN_NOW
  RUN_NOW="${RUN_NOW:-Y}"
  if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/start.sh"
  fi
else
  warn "start.sh tidak ditemukan di $SCRIPT_DIR, jalankan manual: python app.py"
fi
