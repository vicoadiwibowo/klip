#!/data/data/com.termux/files/usr/bin/bash
# AI Video Klip V2 - Auto Installer with FFmpeg Auto-Repair

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

# ------------------------------------------------------------
# STEP 1: Update + upgrade semua paket
# ------------------------------------------------------------
echo -e "${YELLOW}[1/7]${NC} Update Termux (upgrade semua paket)..."
echo "  Ini bisa lama (5-10 menit) di install pertama."
pkg update -y 2>&1 | tail -2 || true
echo "  Upgrade paket lama (untuk fix library mismatch)..."
pkg upgrade -y 2>&1 | tail -3 || true
echo -e "${GREEN}  OK${NC}"
echo ""

# ------------------------------------------------------------
# STEP 2: Install paket dasar
# ------------------------------------------------------------
echo -e "${YELLOW}[2/7]${NC} Install paket dasar (python, git, ffmpeg)..."
pkg install -y python git 2>&1 | tail -2 || true
pkg install -y python-cryptography 2>&1 | tail -2 || true

# ------------------------------------------------------------
# FFmpeg auto-repair
# ------------------------------------------------------------
echo "  Install ffmpeg..."

install_ffmpeg() {
    pkg install -y ffmpeg 2>&1 | tail -3 || true

    # Test apakah ffmpeg bisa jalan
    if ffmpeg -version > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Coba install biasa
if install_ffmpeg; then
    echo -e "${GREEN}  OK ffmpeg terinstall${NC}"
else
    echo -e "${YELLOW}  ⚠ ffmpeg error, coba fix library dependency...${NC}"

    # Fix 1: Reinstall libplacebo (penyebab error libplacebo.so)
    echo "  Fix 1: reinstall libplacebo..."
    pkg install --reinstall -y libplacebo 2>&1 | tail -2 || true

    if install_ffmpeg; then
        echo -e "${GREEN}  OK ffmpeg terinstall (setelah fix libplacebo)${NC}"
    else
        echo -e "${YELLOW}  ⚠ Masih error, coba fix 2: reinstall semua${NC}"

        # Fix 2: Reinstall ffmpeg + libplacebo + semua deps
        pkg install --reinstall -y ffmpeg libplacebo 2>&1 | tail -3 || true

        if install_ffmpeg; then
            echo -e "${GREEN}  OK ffmpeg terinstall (setelah full reinstall)${NC}"
        else
            # Fix 3: Upgrade terakhir, hapus cache
            echo -e "${YELLOW}  ⚠ Masih error, coba fix 3: clean cache + upgrade${NC}"
            apt clean
            pkg upgrade -y 2>&1 | tail -3 || true
            pkg install -y ffmpeg 2>&1 | tail -3 || true

            if install_ffmpeg; then
                echo -e "${GREEN}  OK ffmpeg terinstall${NC}"
            else
                echo -e "${RED}  ✗ ffmpeg tetap error.${NC}"
                echo ""
                echo -e "${YELLOW}  Solusi manual:${NC}"
                echo "  1. Jalankan: termux-change-repo"
                echo "  2. Pilih mirror utama (misal Grimler atau AArch64)"
                echo "  3. Jalankan ulang install.sh"
                echo ""
                echo -e "${YELLOW}  Lanjut install tanpa ffmpeg (aplikasi tidak akan berfungsi penuh)${NC}"
            fi
        fi
    fi
fi

echo ""

# ------------------------------------------------------------
# STEP 3: Download project
# ------------------------------------------------------------
echo -e "${YELLOW}[3/7]${NC} Download project..."
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR" || exit 1
    git pull --quiet 2>/dev/null || true
else
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
fi
cd "$INSTALL_DIR" || exit 1
echo -e "${GREEN}  OK${NC}"

# ------------------------------------------------------------
# STEP 4: Setup folder
# ------------------------------------------------------------
echo -e "${YELLOW}[4/7]${NC} Setup folder runtime..."
mkdir -p downloads clips uploads_srt uploads_music
echo -e "${GREEN}  OK${NC}"

# ------------------------------------------------------------
# STEP 5: Python dependencies
# ------------------------------------------------------------
echo -e "${YELLOW}[5/7]${NC} Install dependencies Python..."
pip install --quiet --upgrade flask requests 2>&1 | grep -v "already satisfied" | tail -1 || true
pip install --quiet --upgrade yt-dlp 2>&1 | grep -v "already satisfied" | tail -1 || true
echo -e "${GREEN}  OK${NC}"

# ------------------------------------------------------------
# STEP 6: API Key
# ------------------------------------------------------------
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   KONFIGURASI API KEY GEMINI${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "  Dapatkan API key gratis di:"
echo -e "  ${CYAN}https://aistudio.google.com/app/apikey${NC}"
echo ""
echo "  Copy key → paste di bawah → Enter"
echo ""

read -p "  Paste API Key Gemini: " GEMINI_KEY
GEMINI_KEY=$(echo "$GEMINI_KEY" | xargs)

if grep -q "GEMINI_API_KEY" ~/.bashrc 2>/dev/null; then
    sed -i '/GEMINI_API_KEY/d' ~/.bashrc
fi
echo "export GEMINI_API_KEY=\"$GEMINI_KEY\"" >> ~/.bashrc
echo -e "${GREEN}  ✓ API Key tersimpan${NC}"
echo ""

# ------------------------------------------------------------
# STEP 7: Verifikasi akhir
# ------------------------------------------------------------
echo -e "${YELLOW}[6/7]${NC} Verifikasi install..."
FFMPEG_STATUS="${RED}✗${NC}"
YOUTUBE_STATUS="${RED}✗${NC}"
PYTHON_STATUS="${RED}✗${NC}"

if ffmpeg -version > /dev/null 2>&1; then
    FFMPEG_STATUS="${GREEN}✓${NC}"
fi
if yt-dlp --version > /dev/null 2>&1; then
    YOUTUBE_STATUS="${GREEN}✓${NC}"
fi
if python -c "import flask" 2>/dev/null; then
    PYTHON_STATUS="${GREEN}✓${NC}"
fi

echo -e "  ${PYTHON_STATUS} Python + Flask"
echo -e "  ${FFMPEG_STATUS} FFmpeg"
echo -e "  ${YOUTUBE_STATUS} yt-dlp"
echo ""

# ------------------------------------------------------------
# SELESAI
# ------------------------------------------------------------
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}         ✅ INSTALL SELESAI             ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "  ${YELLOW}[7/7]${NC} Jalankan aplikasi:"
echo ""
echo -e "  ${GREEN}cd ~/klip${NC}"
echo -e "  ${GREEN}python app.py${NC}"
echo ""
echo "  Buka browser:"
echo -e "  ${CYAN}http://192.168.x.x:5000${NC}"
echo ""
echo -e "  ${YELLOW}Tips: cek IP Termux dengan:${NC}"
echo -e "  ${GREEN}ifconfig wlan0 | grep 'inet '${NC}"
echo ""