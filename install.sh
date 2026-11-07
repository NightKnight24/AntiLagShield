#!/bin/sh
set -e

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Error: Anti-Lag Shield requires iOS or iPadOS." >&2
    exit 1
fi

DEB_NAME="com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb"
DEB_URL="https://raw.githubusercontent.com/NightKnight24/AntiLagShield/main/dist/${DEB_NAME}"
TMP_DEB="/tmp/${DEB_NAME}"

echo "Downloading ${DEB_NAME}..."
rm -f "$TMP_DEB"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$DEB_URL" -o "$TMP_DEB"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$DEB_URL" -O "$TMP_DEB"
else
    echo "Error: curl or wget is required." >&2
    exit 1
fi

if [ ! -s "$TMP_DEB" ]; then
    echo "Error: Downloaded package is empty." >&2
    exit 1
fi

echo "Installing ${DEB_NAME}..."
if [ "$(id -u)" -eq 0 ]; then
    dpkg -i "$TMP_DEB"
elif command -v sudo >/dev/null 2>&1; then
    sudo dpkg -i "$TMP_DEB"
else
    echo "Error: Run as root or with sudo to install Debian packages." >&2
    rm -f "$TMP_DEB"
    exit 1
fi

rm -f "$TMP_DEB"
echo "Anti-Lag Shield v1.0.0 installed. Run 'sbreload' to activate Control Center and Notification Center hooks."
