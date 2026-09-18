#!/data/data/com.termux/files/usr/bin/bash
# AI Video Klip V2 - Auto Installer

set -e

REPO_URL="https://github.com/vicoadiwibowo/klip"
INSTALL_DIR="$HOME/klip"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   AI Video Klip V2 - Installer         ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo -e "${YELLOW}[1/5]${NC} Update paket Termux..."
pkg update -y > /dev/null 2>&1 || true

echo -e "${YELLOW}[2/5]${NC} Install paket dasar..."
pkg install -y python ffmpeg git > /dev/null 2>&1
pkg install -y python-cryptography > /dev/null 2>&1 || true
echo -e "${GREEN}  OK Paket dasar terinstall${NC}"

echo -e "${YELLOW}[3/5]${NC} Download project..."
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR"
    git pull --quiet 2>/dev/null || true
else
    git clone --quiet "$REPO_URL.git" "$INSTALL_DIR" 2>/dev/null || {
        pkg install -y unzip > /dev/null 2>&1
        mkdir -p "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        curl -sL "$REPO_URL/archive/refs/heads/main.zip" -o repo.zip
        unzip -q repo.zip -d /tmp/
        cp -r /tmp/klip-main/* .
        cp -r /tmp/klip-main/.[!.]* . 2>/dev/null || true
        rm -f repo.zip
    }
fi
cd "$INSTALL_DIR"
echo -e "${GREEN}  OK Project: $INSTALL_DIR${NC}"

echo -e "${YELLOW}[4/5]${NC} Setup folder runtime..."
mkdir -p downloads clips uploads_srt uploads_music
echo -e "${GREEN}  OK Folder dibuat${NC}"

echo -e "${YELLOW}[5/5]${NC} Install dependencies Python..."
pip install --quiet --upgrade flask requests 2>&1 | grep -v "already satisfied" || true
pip install --quiet --upgrade yt-dlp 2>&1 | grep -v "already satisfied" || true
echo -e "${GREEN}  OK Dependencies terinstall${NC}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}         INSTALL BERHASIL               ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "  ${YELLOW}LANGKAH SELANJUTNYA:${NC}"
echo ""
echo -e "  ${CYAN}1. Set API Key Gemini:${NC}"
echo -e "     ${GREEN}set-gemini${NC}"
echo ""
echo -e "  ${CYAN}2. Jalankan aplikasi:${NC}"
echo -e "     ${GREEN}cd ~/klip && python app.py${NC}"
echo ""
echo -e "  ${CYAN}3. Buka browser:${NC}"
echo -e "     ${GREEN}http://192.168.x.x:5000${NC}"
echo ""
echo -e "  Dapatkan API key gratis di:"
echo -e "  ${CYAN}https://aistudio.google.com/app/apikey${NC}"
echo ""