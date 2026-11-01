#!/bin/bash
# ==============================================================================
# 📦 Anti-Lag Shield Pro v3.8 Universal Packaging Script
# Builds ready-to-distribute .deb packages (Rootless & Rootful) and TrollStore .tipa
# ==============================================================================

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
    rm -rf "$PKG_TMP"
    mkdir -p "$PKG_TMP"

    # --- 2A. ROOTLESS PACKAGE (iphoneos-arm64 for Sileo, Zebra, Dopamine, palera1n) ---
    ROOTLESS_DIR="$PKG_TMP/rootless"
    mkdir -p "$ROOTLESS_DIR/DEBIAN"
    mkdir -p "$ROOTLESS_DIR/var/jb/Applications"
    mkdir -p "$ROOTLESS_DIR/var/jb/usr/bin"

    cp -R /var/jb/Applications/AntiLagShield.app "$ROOTLESS_DIR/var/jb/Applications/"
    cp /var/jb/usr/bin/shield_ctl "$ROOTLESS_DIR/var/jb/usr/bin/"
    cp /var/jb/usr/bin/shield.sh "$ROOTLESS_DIR/var/jb/usr/bin/"
    chmod 755 "$ROOTLESS_DIR/var/jb/usr/bin/shield_ctl" "$ROOTLESS_DIR/var/jb/usr/bin/shield.sh" "$ROOTLESS_DIR/var/jb/Applications/AntiLagShield.app/AntiLagShield"

    cat <<EOF > "$ROOTLESS_DIR/DEBIAN/control"
Package: com.nightknight.antilagshield
Name: Anti-Lag Shield Pro
Version: 3.8
Architecture: iphoneos-arm64
Description: Universal Network Sentinel & Device Revival suite for iOS & iPadOS.
Maintainer: NightKnight <nightknight24@users.noreply.github.com>
Author: NightKnight24
Section: Utilities
Depends: bash, sudo
EOF

    cat <<'EOF' > "$ROOTLESS_DIR/DEBIAN/postinst"
#!/bin/sh
chmod 755 /var/jb/usr/bin/shield_ctl /var/jb/usr/bin/shield.sh /var/jb/Applications/AntiLagShield.app/AntiLagShield
if which ldid >/dev/null 2>&1; then
    ldid -S /var/jb/Applications/AntiLagShield.app/AntiLagShield 2>/dev/null
fi
if which uicache >/dev/null 2>&1; then
    uicache -p /var/jb/Applications/AntiLagShield.app 2>/dev/null
fi
exit 0
EOF
    chmod 755 "$ROOTLESS_DIR/DEBIAN/postinst"

    cat <<'EOF' > "$ROOTLESS_DIR/DEBIAN/prerm"
#!/bin/sh
if [ -x /var/jb/usr/bin/shield_ctl ]; then
    /var/jb/usr/bin/shield_ctl stop >/dev/null 2>&1
    /var/jb/usr/bin/shield_ctl daemon disable >/dev/null 2>&1
fi
exit 0
EOF
    chmod 755 "$ROOTLESS_DIR/DEBIAN/prerm"

    /var/jb/usr/bin/dpkg-deb -Zgzip -b "$ROOTLESS_DIR" /tmp/AntiLagShield_v3.8_rootless.deb

    # --- 2B. ROOTFUL PACKAGE (iphoneos-arm for checkra1n, unc0ver, Cydia, Sileo) ---
    ROOTFUL_DIR="$PKG_TMP/rootful"
    mkdir -p "$ROOTFUL_DIR/DEBIAN"
    mkdir -p "$ROOTFUL_DIR/Applications"
    mkdir -p "$ROOTFUL_DIR/usr/bin"

    cp -R /var/jb/Applications/AntiLagShield.app "$ROOTFUL_DIR/Applications/"
    cp /var/jb/usr/bin/shield_ctl "$ROOTFUL_DIR/usr/bin/"
    cp /var/jb/usr/bin/shield.sh "$ROOTFUL_DIR/usr/bin/"
    chmod 755 "$ROOTFUL_DIR/usr/bin/shield_ctl" "$ROOTFUL_DIR/usr/bin/shield.sh" "$ROOTFUL_DIR/Applications/AntiLagShield.app/AntiLagShield"

    cat <<EOF > "$ROOTFUL_DIR/DEBIAN/control"
Package: com.nightknight.antilagshield
Name: Anti-Lag Shield Pro
Version: 3.8
Architecture: iphoneos-arm
Description: Universal Network Sentinel & Device Revival suite for iOS & iPadOS.
Maintainer: NightKnight <nightknight24@users.noreply.github.com>
Author: NightKnight24
Section: Utilities
Depends: bash, sudo
EOF

    cat <<'EOF' > "$ROOTFUL_DIR/DEBIAN/postinst"
#!/bin/sh
chmod 755 /usr/bin/shield_ctl /usr/bin/shield.sh /Applications/AntiLagShield.app/AntiLagShield
if which ldid >/dev/null 2>&1; then
    ldid -S /Applications/AntiLagShield.app/AntiLagShield 2>/dev/null
fi
if which uicache >/dev/null 2>&1; then
    uicache -p /Applications/AntiLagShield.app 2>/dev/null
fi
exit 0
EOF
    chmod 755 "$ROOTFUL_DIR/DEBIAN/postinst"

    cat <<'EOF' > "$ROOTFUL_DIR/DEBIAN/prerm"
#!/bin/sh
if [ -x /usr/bin/shield_ctl ]; then
    /usr/bin/shield_ctl stop >/dev/null 2>&1
    /usr/bin/shield_ctl daemon disable >/dev/null 2>&1
fi
exit 0
EOF
    chmod 755 "$ROOTFUL_DIR/DEBIAN/prerm"

    /var/jb/usr/bin/dpkg-deb -Zgzip -b "$ROOTFUL_DIR" /tmp/AntiLagShield_v3.8_rootful.deb

    # --- 2C. TROLLSTORE .TIPA / .IPA BUNDLE ---
    rm -rf /tmp/Payload /tmp/AntiLagShield_v3.8.tipa
    mkdir -p /tmp/Payload
    cp -R /var/jb/Applications/AntiLagShield.app /tmp/Payload/
    cd /tmp && zip -qr /tmp/AntiLagShield_v3.8.tipa Payload/
'

echo "==> 3. Downloading built packages to local dist/ folder..."
scp ipad:/tmp/AntiLagShield_v3.8_rootless.deb "$DIST_DIR/"
scp ipad:/tmp/AntiLagShield_v3.8_rootful.deb "$DIST_DIR/"
scp ipad:/tmp/AntiLagShield_v3.8.tipa "$DIST_DIR/"

echo "==> 4. Generating SHA256 checksums..."
cd "$DIST_DIR"
shasum -a 256 *.deb *.tipa > SHA256SUMS.txt

echo "==> Successfully created distribution packages in $DIST_DIR:"
ls -lh "$DIST_DIR"
