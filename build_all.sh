#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IPAD_HOST="${1:-ipad}"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CFLAGS=(-Wall -Wextra -Werror -arch arm64 -fobjc-arc -isysroot "$SDK_PATH" -miphoneos-version-min=12.0)

echo "==> [1/6] Compiling shield_ctl..."
xcrun -sdk iphoneos clang "${CFLAGS[@]}" \
    -framework Foundation \
    "$DIR/shield_ctl_src/main.m" \
    -o "$DIR/shield_ctl"

echo "==> [2/6] Compiling AntiLagShield.app..."
cp "$DIR/AntiLagShield/Info.plist" "$DIR/AntiLagShield/AntiLagShield.app/Info.plist"
xcrun -sdk iphoneos clang "${CFLAGS[@]}" \
    -framework UIKit -framework Foundation \
    "$DIR/AntiLagShield/main.m" \
    -o "$DIR/AntiLagShield/AntiLagShield.app/AntiLagShield"

echo "==> [3/6] Compiling AntiLagShieldCC.bundle..."
mkdir -p "$DIR/AntiLagShieldCC/AntiLagShieldCC.bundle"
xcrun -sdk iphoneos clang "${CFLAGS[@]}" -bundle -undefined dynamic_lookup \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    "$DIR/AntiLagShieldCC/AntiLagShieldCC.m" \
    -o "$DIR/AntiLagShieldCC/AntiLagShieldCC.bundle/AntiLagShieldCC"

echo "==> [4/6] Compiling AntiLagShieldBanner.dylib..."
mkdir -p "$DIR/AntiLagShieldBanner"
xcrun -sdk iphoneos clang "${CFLAGS[@]}" -shared \
    -framework Foundation -framework UIKit -framework UserNotifications \
    "$DIR/AntiLagShieldBanner/Tweak.m" \
    -o "$DIR/AntiLagShieldBanner/AntiLagShieldBanner.dylib"

echo "==> [5/6] Deploying binaries to $IPAD_HOST..."
ssh "$IPAD_HOST" "rm -rf /tmp/als_stage && mkdir -p /tmp/als_stage"
scp "$DIR/shield_ctl" "$IPAD_HOST:/tmp/als_stage/shield_ctl"
scp "$DIR/shield_ctl_src/entitlements.plist" "$IPAD_HOST:/tmp/als_stage/ctl_entitlements.plist"
scp "$DIR/AntiLagShield/AntiLagShield.app/AntiLagShield" "$IPAD_HOST:/tmp/als_stage/AntiLagShield"
scp "$DIR/AntiLagShield/AntiLagShield.app/Info.plist" "$IPAD_HOST:/tmp/als_stage/Info.plist"
scp "$DIR/AntiLagShield/entitlements.plist" "$IPAD_HOST:/tmp/als_stage/app_entitlements.plist"
scp -r "$DIR/AntiLagShieldCC/AntiLagShieldCC.bundle" "$IPAD_HOST:/tmp/als_stage/AntiLagShieldCC.bundle"
scp "$DIR/AntiLagShieldBanner/AntiLagShieldBanner.dylib" "$IPAD_HOST:/tmp/als_stage/AntiLagShieldBanner.dylib"
scp "$DIR/AntiLagShieldBanner/AntiLagShieldBanner.plist" "$IPAD_HOST:/tmp/als_stage/AntiLagShieldBanner.plist"

ssh "$IPAD_HOST" "
    set -e
    sudo cp /tmp/als_stage/shield_ctl /var/jb/usr/bin/shield_ctl
    sudo chown 0:0 /var/jb/usr/bin/shield_ctl
    sudo chmod 6755 /var/jb/usr/bin/shield_ctl
    sudo /var/jb/usr/bin/ldid -S/tmp/als_stage/ctl_entitlements.plist /var/jb/usr/bin/shield_ctl

    sudo cp /tmp/als_stage/AntiLagShield /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo cp /tmp/als_stage/Info.plist /var/jb/Applications/AntiLagShield.app/Info.plist
    sudo chown -R 0:0 /var/jb/Applications/AntiLagShield.app
    sudo chmod 755 /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo chmod 644 /var/jb/Applications/AntiLagShield.app/Info.plist
    sudo /var/jb/usr/bin/ldid -S/tmp/als_stage/app_entitlements.plist /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo /var/jb/usr/bin/uicache -p /var/jb/Applications/AntiLagShield.app

    sudo rm -rf /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle
    sudo cp -R /tmp/als_stage/AntiLagShieldCC.bundle /var/jb/Library/ControlCenter/Bundles/
    sudo chown -R 0:0 /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle
    sudo chmod 755 /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle/AntiLagShieldCC
    sudo /var/jb/usr/bin/ldid -S /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle/AntiLagShieldCC

    sudo cp /tmp/als_stage/AntiLagShieldBanner.dylib /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib
    sudo cp /tmp/als_stage/AntiLagShieldBanner.plist /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.plist
    sudo chown 0:0 /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.plist
    sudo chmod 755 /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib
    sudo chmod 644 /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.plist
    sudo /var/jb/usr/bin/ldid -S /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib

    sudo rm -rf /tmp/als_stage
"

echo "==> [6/6] Packaging com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb..."
ssh "$IPAD_HOST" '
    set -e
    PKG_TMP="/tmp/als_deb_build"
    sudo rm -rf "$PKG_TMP"
    sudo mkdir -p "$PKG_TMP/rootless/DEBIAN"
    sudo mkdir -p "$PKG_TMP/rootless/var/jb/Applications"
    sudo mkdir -p "$PKG_TMP/rootless/var/jb/usr/bin"
    sudo mkdir -p "$PKG_TMP/rootless/var/jb/Library/ControlCenter/Bundles"
    sudo mkdir -p "$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries"

    sudo cp -R /var/jb/Applications/AntiLagShield.app "$PKG_TMP/rootless/var/jb/Applications/"
    sudo cp /var/jb/usr/bin/shield_ctl "$PKG_TMP/rootless/var/jb/usr/bin/"
    sudo cp -R /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle "$PKG_TMP/rootless/var/jb/Library/ControlCenter/Bundles/"
    sudo cp /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib "$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries/"
    sudo cp /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.plist "$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries/"

    sudo chown -R 0:0 "$PKG_TMP/rootless"
    sudo chmod 6755 "$PKG_TMP/rootless/var/jb/usr/bin/shield_ctl"
    sudo chmod 755 "$PKG_TMP/rootless/var/jb/Applications/AntiLagShield.app/AntiLagShield"
    sudo chmod 644 "$PKG_TMP/rootless/var/jb/Applications/AntiLagShield.app/Info.plist"
    sudo chmod 644 "$PKG_TMP/rootless/var/jb/Applications/AntiLagShield.app/"*.png
    sudo chmod 755 "$PKG_TMP/rootless/var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle/AntiLagShieldCC"
    sudo chmod 755 "$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries/AntiLagShieldBanner.dylib"
    sudo chmod 644 "$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries/AntiLagShieldBanner.plist"

    cat << "CONTROL_EOF" | sudo tee "$PKG_TMP/rootless/DEBIAN/control" >/dev/null
Package: com.nightknight.antilagshield
Name: Anti-Lag Shield
Version: 1.0.0
Architecture: iphoneos-arm64
Description: XNU socket buffer, TCP delayed-ACK, and radio coexistence tuning utility with Control Center and Notification Center quick-toggles.
Maintainer: NightKnight24 <nightknight24@users.noreply.github.com>
Author: NightKnight24
Section: System
Depends: firmware (>= 12.0)
CONTROL_EOF

    cat << "POSTINST_EOF" | sudo tee "$PKG_TMP/rootless/DEBIAN/postinst" >/dev/null
#!/bin/sh
chown 0:0 /var/jb/usr/bin/shield_ctl 2>/dev/null || true
chmod 6755 /var/jb/usr/bin/shield_ctl 2>/dev/null || true
if command -v uicache >/dev/null 2>&1; then
    uicache -p /var/jb/Applications/AntiLagShield.app 2>/dev/null || true
elif [ -x /var/jb/usr/bin/uicache ]; then
    /var/jb/usr/bin/uicache -p /var/jb/Applications/AntiLagShield.app 2>/dev/null || true
fi
exit 0
POSTINST_EOF

    cat << "PRERM_EOF" | sudo tee "$PKG_TMP/rootless/DEBIAN/prerm" >/dev/null
#!/bin/sh
if [ -x /var/jb/usr/bin/shield_ctl ]; then
    /var/jb/usr/bin/shield_ctl daemon disable 2>/dev/null || true
    /var/jb/usr/bin/shield_ctl stop 2>/dev/null || true
fi
exit 0
PRERM_EOF

    sudo chmod 755 "$PKG_TMP/rootless/DEBIAN/postinst" "$PKG_TMP/rootless/DEBIAN/prerm"
    sudo /var/jb/usr/bin/dpkg-deb --root-owner-group -Zgzip -b "$PKG_TMP/rootless" /tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb
    sudo chmod 644 /tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb
    sudo rm -rf "$PKG_TMP"
'

mkdir -p "$DIR/dist"
scp "$IPAD_HOST:/tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb" "$DIR/dist/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb"
cp "$DIR/dist/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb" "$HOME/Desktop/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb"
cp "$DIR/dist/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb" "$HOME/Downloads/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb"
ssh "$IPAD_HOST" "sudo rm -f /tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb"

echo "==> Build and packaging complete."
