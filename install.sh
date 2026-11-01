#!/bin/sh
# ==============================================================================
# 🛡️ Anti-Lag Shield Pro v3.8 Universal Auto-Installer
# For all 64-bit iOS & iPadOS Devices (Rootless & Rootful)
# Usage: curl -sL https://raw.githubusercontent.com/NightKnight24/AntiLagShield/main/install.sh | bash
# ==============================================================================

set -e

C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'

echo ""
echo "${C_CYAN}================================================================${C_RESET}"
echo "${C_CYAN}🛡️   Anti-Lag Shield Pro v3.8 — Universal Device Installer    🛡️${C_RESET}"
echo "${C_CYAN}================================================================${C_RESET}"
echo ""

# Verify OS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "${C_RED}[!] Error: This installer is intended for iOS & iPadOS devices only.${C_RESET}"
    exit 1
fi

# Detect Environment
if [ -d "/var/jb" ]; then
    JB_MODE="rootless"
    JB_PREFIX="/var/jb"
    DEB_URL="https://raw.githubusercontent.com/NightKnight24/AntiLagShield/main/dist/AntiLagShield_v3.8_rootless.deb"
else
    JB_MODE="rootful"
    JB_PREFIX=""
    DEB_URL="https://raw.githubusercontent.com/NightKnight24/AntiLagShield/main/dist/AntiLagShield_v3.8_rootful.deb"
fi

echo "${C_CYAN}[*] Detected Environment:${C_RESET} ${C_GREEN}${JB_MODE}${C_RESET} (Prefix: ${JB_PREFIX:-/})"
echo "${C_CYAN}[*] Downloading Anti-Lag Shield Pro v3.8 package...${C_RESET}"

TMP_DEB="/tmp/antilagshield.deb"
rm -f "$TMP_DEB"

if which curl >/dev/null 2>&1; then
    curl -sSL "$DEB_URL" -o "$TMP_DEB" 2>/dev/null || true
elif which wget >/dev/null 2>&1; then
    wget -q "$DEB_URL" -O "$TMP_DEB" 2>/dev/null || true
fi

# Fallback: if download is empty (e.g. repo not published yet), install directly if local
if [ ! -s "$TMP_DEB" ]; then
    echo "${C_YELLOW}[!] Remote download not available yet. Looking for local package...${C_RESET}"
    if [ -f "/tmp/AntiLagShield_v3.8_${JB_MODE}.deb" ]; then
        cp "/tmp/AntiLagShield_v3.8_${JB_MODE}.deb" "$TMP_DEB"
    fi
fi

if [ -s "$TMP_DEB" ]; then
    echo "${C_CYAN}[*] Installing package via dpkg...${C_RESET}"
    if which sudo >/dev/null 2>&1; then
        sudo dpkg -i "$TMP_DEB"
    else
        dpkg -i "$TMP_DEB"
    fi
    rm -f "$TMP_DEB"
else
    echo "${C_RED}[!] Could not locate or download installation package.${C_RESET}"
    echo "Please visit: https://github.com/NightKnight24 to download the .deb manually."
    exit 1
fi

echo ""
echo "${C_GREEN}[✔] Anti-Lag Shield Pro v3.8 successfully installed!${C_RESET}"
echo ""
echo "🚀 Getting Started:"
echo "  • Open the 'Anti-Lag Shield' app on your Home Screen."
echo "  • Or run the interactive HUD in terminal: ${C_CYAN}shield.sh${C_RESET}"
echo "  • View status anytime: ${C_CYAN}shield_ctl status${C_RESET}"
echo ""
