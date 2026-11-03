#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$DIR/dist"
mkdir -p "$DIST_DIR"

echo "==> 1. Compiling latest AntiLagShield binary..."
cd "$DIR/AntiLagShield"
./build.sh

echo "==> 2. Building Debian packages on iPad..."
ssh ipad '
    set -e
    PKG_TMP="/tmp/pkg_build"
    sudo rm -rf "$PKG_TMP"
    sudo mkdir -p "$PKG_TMP"

    # --- 2A. ROOTLESS PACKAGE (iphoneos-arm64 for Sileo, Zebra, Dopamine, palera1n) ---
    ROOTLESS_DIR="$PKG_TMP/rootless"
    sudo mkdir -p "$ROOTLESS_DIR/DEBIAN"
    sudo mkdir -p "$ROOTLESS_DIR/var/jb/Applications"
    sudo mkdir -p "$ROOTLESS_DIR/var/jb/usr/bin"

    sudo cp -R /var/jb/Applications/AntiLagShield.app "$ROOTLESS_DIR/var/jb/Applications/"
    sudo cp /var/jb/usr/bin/shield_ctl "$ROOTLESS_DIR/var/jb/usr/bin/"
    
    sudo chown -R 0:0 "$ROOTLESS_DIR"
    sudo chmod 755 "$ROOTLESS_DIR/var/jb/usr/bin/shield_ctl"
    sudo chmod 755 "$ROOTLESS_DIR/var/jb/Applications/AntiLagShield.app/AntiLagShield"
    sudo chmod 644 "$ROOTLESS_DIR/var/jb/Applications/AntiLagShield.app/Info.plist"
    sudo chmod 644 "$ROOTLESS_DIR/var/jb/Applications/AntiLagShield.app/"*.png

    sudo bash -c "cat << 'CONTROL_EOF' > '$ROOTLESS_DIR/DEBIAN/control'
Package: com.nightknight.antilagshield
Name: Anti-Lag Shield
Version: 1.0.0
Architecture: iphoneos-arm64
Description: Network buffer & latency tuning utility for iPadOS & iOS.
Maintainer: Jordan Allison <nightknight24@users.noreply.github.com>
Author: Jordan Allison
Section: Applications
Depends: firmware (>= 12.0)
CONTROL_EOF"

    sudo bash -c "cat << 'POSTINST_EOF' > '$ROOTLESS_DIR/DEBIAN/postinst'
#!/bin/sh
if which uicache >/dev/null 2>&1; then
    uicache -p /var/jb/Applications/AntiLagShield.app 2>/dev/null
fi
exit 0
POSTINST_EOF"
    sudo chmod 755 "$ROOTLESS_DIR/DEBIAN/postinst"

    sudo /var/jb/usr/bin/dpkg-deb --root-owner-group -Zgzip -b "$ROOTLESS_DIR" /tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb
    sudo chmod 666 /tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb
'

echo "==> 3. Downloading built package to local dist/ folder..."
scp ipad:/tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb "$DIST_DIR/"
cp "$DIST_DIR/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb" ~/Desktop/
cp "$DIST_DIR/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb" ~/Downloads/

echo "==> 4. Generating SHA256 checksums..."
cd "$DIST_DIR"
shasum -a 256 *.deb > SHA256SUMS.txt

echo "==> Successfully created standard Debian package on Desktop and Downloads!"
ls -lh ~/Desktop/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb
