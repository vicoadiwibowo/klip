#!/data/data/com.termux/files/usr/bin/bash
# AI Video Klip V2 - Auto Installer with API Key Input

set -e

REPO_URL="https://github.com/vicoadiwibowo/klip"
INSTALL_DIR="$HOME/klip"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

clear

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
# STEP 6: INPUT API KEY
# ============================================================
echo ""
echo -e "${YELLOW}[6/6]${NC} Konfigurasi API Key Gemini"
echo ""

# Bersihkan layar biar fokus
clear

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                ║${NC}"
echo -e "${CYAN}║   ${BOLD}LANGKAH TERAKHIR: PASTE API KEY GEMINI${NC}${CYAN}       ║${NC}"
echo -e "${CYAN}║                                                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Belum punya API key?${NC}"
echo -e "  Buka di browser: ${CYAN}https://aistudio.google.com/app/apikey${NC}"
echo -e "  Login Google → klik ${BOLD}Create API key${NC} → Copy"
echo ""
echo -e "  ${BOLD}Cara paste di Termux:${NC}"
echo -e "  1. Ketuk dan tahan di area terminal"
echo -e "  2. Pilih ${GREEN}Paste${NC}"
echo -e "  3. Key akan muncul di bawah"
echo -e "  4. Tekan ${GREEN}Enter${NC}"
echo ""
echo -e "${YELLOW}  ⬇️  PASTE API KEY DI BAWAH INI (jangan tekan Enter dulu):${NC}"
echo ""

# Loop sampai dapat input yang tidak kosong
GEMINI_KEY=""
while [ -z "$GEMINI_KEY" ]; do
    echo -ne "  ${BOLD}${GREEN}▶${NC} "
    read GEMINI_KEY
    GEMINI_KEY=$(echo "$GEMINI_KEY" | xargs)

    if [ -z "$GEMINI_KEY" ]; then
        echo ""
        echo -e "  ${RED}✗ Input kosong. Silakan paste API key dulu.${NC}"
        echo ""
        echo -e "  ${YELLOW}Ketik ${BOLD}skip${NC}${YELLOW} kalau mau isi nanti manual:${NC}"
        echo -ne "  ${BOLD}${GREEN}▶${NC} "
        read GEMINI_KEY
        GEMINI_KEY=$(echo "$GEMINI_KEY" | xargs)

        if [ "$GEMINI_KEY" = "skip" ] || [ "$GEMINI_KEY" = "SKIP" ]; then
            echo ""
            echo -e "  ${YELLOW}⏭  Skip. Set manual nanti dengan:${NC}"
            echo -e "  ${GREEN}echo 'export GEMINI_API_KEY=\"KEY_ANDA\"' >> ~/.bashrc${NC}"
            echo -e "  ${GREEN}source ~/.bashrc${NC}"
            GEMINI_KEY=""
            break
        fi
    fi
done

# Simpan kalau ada key
if [ -n "$GEMINI_KEY" ]; then
    # Hapus key lama kalau ada
    if grep -q "GEMINI_API_KEY" ~/.bashrc 2>/dev/null; then
        sed -i '/GEMINI_API_KEY/d' ~/.bashrc
    fi
    echo "export GEMINI_API_KEY=\"$GEMINI_KEY\"" >> ~/.bashrc

    echo ""
    echo -e "  ${GREEN}✓ API Key tersimpan!${NC}"
    echo ""

    # Export untuk sesi ini juga
    export GEMINI_API_KEY="$GEMINI_KEY"

    # Test key
    echo -e "  ${YELLOW}⏳ Test API key...${NC}"
    TEST_RESPONSE=$(curl -s -X POST \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_KEY" \
        -H "Content-Type: application/json" \
        -d '{"contents":[{"parts":[{"text":"hi"}]}]}' \
        -m 20 2>&1)

    if echo "$TEST_RESPONSE" | grep -q '"text"'; then
        echo -e "  ${GREEN}✓ API Key valid & aktif!${NC}"
    elif echo "$TEST_RESPONSE" | grep -q '"error"'; then
        ERR_MSG=$(echo "$TEST_RESPONSE" | grep -o '"message":"[^"]*"' | head -1)
        echo -e "  ${RED}✗ API Key error: $ERR_MSG${NC}"
        echo -e "  ${YELLOW}  Cek key di: https://aistudio.google.com/app/apikey${NC}"
    else
        echo -e "  ${YELLOW}⚠  Tidak bisa verifikasi (mungkin jaringan). Coba jalankan aplikasi.${NC}"
    fi
fi

# ============================================================
# SELESAI
# ============================================================
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}         ✅ INSTALL BERHASIL             ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "  ${BOLD}Jalankan aplikasi:${NC}"
echo ""
echo -e "  ${GREEN}cd ~/klip${NC}"
echo -e "  ${GREEN}python app.py${NC}"
echo ""
echo -e "  Lalu buka browser:"
echo -e "  ${CYAN}http://192.168.x.x:5000${NC}"
echo ""
echo -e "  ${BOLD}Kalau browser tidak bisa akses, cek IP Termux:${NC}"
echo -e "  ${GREEN}ifconfig${NC}"
echo ""