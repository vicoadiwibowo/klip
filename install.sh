#!/data/data/com.termux/files/usr/bin/bash
# AI Video Klip V2 - Installer

REPO_URL="https://github.com/vicoadiwibowo/klip"
INSTALL_DIR="$HOME/klip"

echo ""
echo "=================================="
echo "  AI Video Klip V2 - Installer"
echo "=================================="
echo ""

echo "[1/6] Update daftar paket..."
pkg update -y 2>&1 | tail -2 || true
echo "  OK"
echo ""

echo "[2/6] Install paket dasar..."
for p in python git ffmpeg; do
    echo "  Install $p..."
    pkg install -y "$p" 2>&1 | tail -1 || true
done
echo "  OK"
echo ""

echo "[3/6] Download project..."
cd "$HOME" || exit 1
rm -rf "$INSTALL_DIR" 2>/dev/null || true
git clone --quiet "$REPO_URL.git" "$INSTALL_DIR" 2>/dev/null || {
    echo "  Git gagal, coba ZIP..."
    pkg install -y unzip 2>&1 | tail -1 || true
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit 1
    curl -sL "$REPO_URL/archive/refs/heads/main.zip" -o repo.zip
    unzip -q repo.zip -d /tmp/ 2>/dev/null
    cp -r /tmp/klip-main/* . 2>/dev/null || true
    rm -f repo.zip
}
cd "$INSTALL_DIR" || exit 1
echo "  OK"
echo ""

echo "[4/6] Setup folder..."
mkdir -p downloads clips uploads_srt uploads_music
echo "  OK"
echo ""

echo "[5/6] Install Python dependencies..."
pip install --quiet --upgrade flask requests 2>&1 | grep -v "already" | tail -1 || true
pip install --quiet --upgrade yt-dlp 2>&1 | grep -v "already" | tail -1 || true
echo "  OK"
echo ""

clear
echo ""
echo "=================================="
echo "  MASUKKAN API KEY GEMINI"
echo "=================================="
echo ""
echo "  Belum punya? Buka:"
echo "  https://aistudio.google.com/app/apikey"
echo ""
echo "  Cara paste: ketuk-tahan di terminal,"
echo "  pilih Paste, lalu tekan Enter."
echo ""
echo "  PASTE API KEY DI BAWAH INI:"
echo ""
printf "  > "

GEMINI_KEY=""
while [ -z "$GEMINI_KEY" ]; do
    read GEMINI_KEY < /dev/tty
    GEMINI_KEY=$(echo "$GEMINI_KEY" | xargs)
    if [ -z "$GEMINI_KEY" ]; then
        echo "  Kosong. Paste lagi:"
        printf "  > "
    fi
done

sed -i '/GEMINI_API_KEY/d' ~/.bashrc 2>/dev/null || true
echo "export GEMINI_API_KEY=\"$GEMINI_KEY\"" >> ~/.bashrc
export GEMINI_API_KEY="$GEMINI_KEY"

echo ""
echo "  API Key tersimpan!"
echo ""

echo "[6/6] Verifikasi..."
if ffmpeg -version > /dev/null 2>&1; then
    echo "  OK FFmpeg"
else
    echo "  X FFmpeg belum terinstall (coba: pkg install ffmpeg)"
fi
if python -c "import flask" 2>/dev/null; then
    echo "  OK Python Flask"
else
    echo "  X Python Flask tidak ada"
fi
echo ""

echo "=================================="
echo "       INSTALL SELESAI"
echo "=================================="
echo ""
echo "  Jalankan:"
echo "    cd ~/klip"
echo "    python app.py"
echo ""
echo "  Buka browser: http://192.168.x.x:5000"
echo ""