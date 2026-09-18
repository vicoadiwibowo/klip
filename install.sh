#!/data/data/com.termux/files/usr/bin/bash
# AI Video Klip V2 - Auto Installer

set -e

REPO_URL="https://github.com/vicoadiwibowo/klip"
INSTALL_DIR="$HOME/klip"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   AI Video Klip V2 - Installer         ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo -e "${YELLOW}[1/6]${NC} Update paket Termux..."
pkg update -y > /dev/null 2>&1 || true

echo -e "${YELLOW}[2/6]${NC} Install paket dasar..."
pkg install -y python ffmpeg git > /dev/null 2>&1
pkg install -y python-cryptography > /dev/null 2>&1 || true
echo -e "${GREEN}  OK Paket dasar terinstall${NC}"

echo -e "${YELLOW}[3/6]${NC} Download project..."
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR"
    git pull --quiet 2>/dev/null || true
else
    git clone --quiet "$REPO_URL.git" "$INSTALL_DIR" 2>/dev/null || {
        echo -e "${YELLOW}  git clone gagal, coba ZIP...${NC}"
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

echo -e "${YELLOW}[4/6]${NC} Setup folder runtime..."
mkdir -p downloads clips uploads_srt uploads_music
echo -e "${GREEN}  OK Folder dibuat${NC}"

echo -e "${YELLOW}[5/6]${NC} Install dependencies Python..."
pip install --quiet --upgrade flask requests 2>&1 | grep -v "already satisfied" || true
pip install --quiet --upgrade yt-dlp 2>&1 | grep -v "already satisfied" || true
echo -e "${GREEN}  OK Dependencies terinstall${NC}"

# ============================================================
# KONFIGURASI API KEY GEMINI - ROBUST VERSION
# ============================================================

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}   KONFIGURASI API KEY GEMINI${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""
echo "  Cara mendapatkan API key:"
echo "  1. Buka: https://aistudio.google.com/app/apikey"
echo "  2. Login dengan akun Google"
echo "  3. Klik tombol 'Create API key'"
echo "  4. Copy key yang muncul"
echo ""
echo -e "  ${YELLOW}Tips:${NC}"
echo "  - Key biasanya diawali dengan 'AIzaSy...'"
echo "  - Paste dengan cara: ketuk dan tahan di terminal, pilih Paste"
echo "  - Jangan tekan Enter dulu sebelum key muncul di layar"
echo ""
echo -e "  Ketik ${RED}skip${NC} kalau mau isi API key nanti secara manual."
echo ""

# Loop minta input sampai dapat
GEMINI_KEY=""
while [ -z "$GEMINI_KEY" ]; do
    echo -n "  Paste API Key Gemini: "
    read GEMINI_KEY
    GEMINI_KEY=$(echo "$GEMINI_KEY" | xargs)  # trim whitespace

    if [ "$GEMINI_KEY" = "skip" ] || [ "$GEMINI_KEY" = "SKIP" ]; then
        echo ""
        echo -e "${YELLOW}  ⏭  Skip. Anda bisa set manual nanti dengan perintah:${NC}"
        echo -e "  ${GREEN}echo 'export GEMINI_API_KEY=\"ISI_KEY_DISINI\"' >> ~/.bashrc${NC}"
        echo -e "  ${GREEN}source ~/.bashrc${NC}"
        GEMINI_KEY=""
        break
    fi

    if [ -z "$GEMINI_KEY" ]; then
        echo -e "${RED}  ✗ Input kosong. Coba lagi, atau ketik 'skip'.${NC}"
        echo ""
    fi
done

# Simpan kalau ada key
if [ -n "$GEMINI_KEY" ]; then
    # Tampilkan preview (aman, hanya 20 karakter awal + akhir)
    KEY_LEN=${#GEMINI_KEY}
    if [ "$KEY_LEN" -gt 25 ]; then
        PREVIEW="${GEMINI_KEY:0:15}...${GEMINI_KEY: -5}"
    else
        PREVIEW="$GEMINI_KEY"
    fi

    echo ""
    echo -e "  Key yang akan disimpan: ${CYAN}$PREVIEW${NC}"
    echo -n "  Benar? (y/n): "
    read CONFIRM
    CONFIRM=$(echo "$CONFIRM" | xargs)

    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || [ "$CONFIRM" = "yes" ]; then
        # Hapus key lama kalau ada
        if grep -q "GEMINI_API_KEY" ~/.bashrc 2>/dev/null; then
            sed -i '/GEMINI_API_KEY/d' ~/.bashrc
        fi
        echo "export GEMINI_API_KEY=\"$GEMINI_KEY\"" >> ~/.bashrc
        echo -e "${GREEN}  ✓ API key tersimpan di ~/.bashrc${NC}"
    else
        echo -e "${YELLOW}  ⏭  Dibatalkan. Set manual nanti.${NC}"
    fi
fi

# ============================================================
# SELESAI
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}         INSTALL BERHASIL               ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "  Untuk menjalankan:"
echo ""
echo -e "  ${GREEN}source ~/.bashrc${NC}"
echo -e "  ${GREEN}cd ~/klip${NC}"
echo -e "  ${GREEN}python app.py${NC}"
echo ""
echo "  Buka browser:"
echo -e "  ${CYAN}http://192.168.x.x:5000${NC}"
echo ""
echo -e "  ${YELLOW}Kalau API key belum di-set:${NC}"
echo -e "  ${GREEN}export GEMINI_API_KEY=\"ISI_KEY_ANDA\"${NC}"
echo -e "  ${GREEN}cd ~/klip && python app.py${NC}"
echo ""