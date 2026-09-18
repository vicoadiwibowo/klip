#!/data/data/com.termux/files/usr/bin/bash
# AI Video Klip V2 - Auto Installer (Safe Mode)

REPO_URL="https://github.com/vicoadiwibowo/klip"
INSTALL_DIR="$HOME/klip"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   AI Video Klip V2 - Installer         ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ------------------------------------------------------------
# STEP 1: Update repo list saja (bukan upgrade)
# ------------------------------------------------------------
echo -e "${YELLOW}[1/6]${NC} Update daftar paket..."
pkg update -y 2>&1 | tail -2 || true
echo -e "${GREEN}  OK${NC}"
echo ""

# ------------------------------------------------------------
# STEP 2: Install paket yang dibutuhkan
# ------------------------------------------------------------
echo -e "${YELLOW}[2/6]${NC} Install paket dasar..."

# Install satu per satu dengan error handling
for pkg_name in python git ffmpeg; do
    echo -e "  Install ${BOLD}$pkg_name${NC}..."
    pkg install -y "$pkg_name" 2>&1 | tail -1 || true
done

# Cek ffmpeg
if ! ffmpeg -version > /dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ ffmpeg error, coba reinstall${NC}"
    pkg install --reinstall -y ffmpeg 2>&1 | tail -2 || true
fi

# Cek git
if ! git --version > /dev/null 2>&1; then
    echo -e "${RED}  ✗ git tidak terinstall${NC}"
    exit 1
fi

echo -e "${GREEN}  OK${NC}"
echo ""

# ------------------------------------------------------------
# STEP 3: Download project
# ------------------------------------------------------------
echo -e "${YELLOW}[3/6]${NC} Download project..."

cd "$HOME" || exit 1

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi

if ! git clone --quiet "$REPO_URL.git" "$INSTALL_DIR" 2>/dev/null; then
    echo -e "${YELLOW}  git clone gagal, coba ZIP...${NC}"
    pkg install -y unzip 2>&1 | tail -1 || true
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit 1
    curl -sL "$REPO_URL/archive/refs/heads/main.zip" -o repo.zip
    unzip -q repo.zip -d /tmp/ 2>/dev/null
    cp -r /tmp/klip-main/* . 2>/dev/null || true
    cp -r /tmp/klip-main/.[!.]* . 2>/dev/null || true
    rm -f repo.zip
fi

cd "$INSTALL_DIR" || exit 1
echo -e "${GREEN}  OK${NC}"

# ------------------------------------------------------------
# STEP 4: Setup folder
# ------------------------------------------------------------
echo -e "${YELLOW}[4/6]${NC} Setup folder..."
mkdir -p downloads clips uploads_srt uploads_music
echo -e "${GREEN}  OK${NC}"

# ------------------------------------------------------------
# STEP 5: Python deps
# ------------------------------------------------------------
echo -e "${YELLOW}[5/6]${NC} Install dependencies Python..."
pip install --quiet --upgrade flask requests 2>&1 | grep -v "already satisfied" | tail -1 || true
pip install --quiet --upgrade yt-dlp 2>&1 | grep -v "already satisfied" | tail -1 || true
echo -e "${GREEN}  OK${NC}"
echo ""

# ------------------------------------------------------------
# STEP 6: API KEY
# ------------------------------------------------------------
clear

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                ║${NC}"
echo -e "${CYAN}║   ${BOLD}${YELLOW}MASUKKAN API KEY GEMINI${NC}${CYAN}                    ║${NC}"
echo -e "${CYAN}║                                                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Belum punya API key?${NC}"
echo -e "  Buka browser: ${CYAN}https://aistudio.google.com/app/apikey${NC}"
echo -e "  Login Google → klik ${BOLD}Create API key${NC} → ${BOLD}COPY${NC}"
echo ""
echo -e "  ${BOLD}Cara paste di Termux:${NC}"
echo -e "  Ketuk dan tahan di area terminal → Paste → Enter"
echo ""
echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  ⬇  PASTE API KEY DI BAWAH INI  ⬇${NC}"
echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"
echo ""

GEMINI_KEY=""
while [ -z "$GEMINI_KEY" ]; do
    printf "  ${BOLD}${GREEN}▶ ${NC}"
    read GEMINI_KEY < /dev/tty
    GEMINI_KEY=$(echo "$GEMINI_KEY" | xargs)
    if [ -z "$GEMINI_KEY" ]; then
        echo -e "  ${RED}✗ Kosong. Paste key dulu, baru Enter.${NC}"
        echo ""
    fi
done

if grep -q "GEMINI_API_KEY" ~/.bashrc 2>/dev/null; then
    sed -i '/GEMINI_API_KEY/d' ~/.bashrc
fi
echo "export GEMINI_API_KEY=\"$GEMINI_KEY\"" >> ~/.bashrc
export GEMINI_API_KEY="$GEMINI_KEY"

echo ""
echo -e "  ${GREEN}✓ API Key tersimpan${NC}"
echo ""

# ------------------------------------------------------------
# VERIFIKASI & SELESAI
# ------------------------------------------------------------
echo -e "${YELLOW}[6/6]${NC} Verifikasi..."
FF="${RED}✗${NC}"; YT="${RED}✗${NC}"; PY="${RED}✗${NC}"
ffmpeg -version > /dev/null 2>&1 && FF="${GREEN}✓${NC}"
yt-dlp --version > /dev/null 2>&1 && YT="${GREEN}✓${NC}"
python -c "import flask" 2>/dev/null && PY="${GREEN}✓${NC}"
echo -e "  ${PY} Python + Flask"
echo -e "  ${FF} FFmpeg"
echo -e "  ${YT} yt-dlp"
echo ""

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}         ✅ INSTALL SELESAI             ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "  Jalankan:"
echo -e "  ${GREEN}cd ~/klip${NC}"
echo -e "  ${GREEN}python app.py${NC}"
echo ""
echo -e "  Buka browser:"
echo -e "  ${CYAN}http://192.168.x.x:5000${NC}"
echo ""