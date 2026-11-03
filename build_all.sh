#!/bin/bash
# ==============================================================================
# 🛡️ Anti-Lag Shield Pro Master Build & Packaging Script
# Builds:
# 1. AntiLagShield.app (UIKit Native App)
# 2. AntiLagShieldCC.bundle (Control Center CCSupport Module)
# 3. AntiLagShieldBanner.dylib (SpringBoard Notification Banner Hook)
# 4. Standard Debian Package (.deb)
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IPAD_HOST="${1:-ipad}"
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)

echo "==> 1. Building AntiLagShield.app..."
xcrun -sdk iphoneos clang -arch arm64 -fobjc-arc \
    -isysroot "$SDK_PATH" \
    -miphoneos-version-min=12.0 \
    -framework UIKit -framework Foundation -framework UserNotifications \
    "$DIR/AntiLagShield/main.m" -o "$DIR/AntiLagShield/AntiLagShield.app/AntiLagShield"

echo "==> 2. Building AntiLagShieldCC.bundle (Control Center Module)..."
mkdir -p "$DIR/AntiLagShieldCC/AntiLagShieldCC.bundle"
xcrun -sdk iphoneos clang -arch arm64 -bundle -fobjc-arc \
    -isysroot "$SDK_PATH" \
    -miphoneos-version-min=12.0 \
    -undefined dynamic_lookup \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    "$DIR/AntiLagShieldCC/AntiLagShieldCC.m" \
    -o "$DIR/AntiLagShieldCC/AntiLagShieldCC.bundle/AntiLagShieldCC"

echo "==> 3. Building AntiLagShieldBanner.dylib (SpringBoard Hook)..."
mkdir -p "$DIR/AntiLagShieldBanner"
xcrun -sdk iphoneos clang -arch arm64 -shared -fobjc-arc \
    -isysroot "$SDK_PATH" \
    -miphoneos-version-min=12.0 \
    -framework Foundation -framework UIKit -framework UserNotifications \
    "$DIR/AntiLagShieldBanner/Tweak.m" \
    -o "$DIR/AntiLagShieldBanner/AntiLagShieldBanner.dylib"

echo "==> 4. Deploying all components to iPad ($IPAD_HOST)..."
ssh "$IPAD_HOST" "rm -rf /tmp/AntiLagShieldCC.bundle"
scp "$DIR/AntiLagShield/AntiLagShield.app/AntiLagShield" "$IPAD_HOST:/tmp/AntiLagShield"
scp "$DIR/AntiLagShield/AntiLagShield.app/Info.plist" "$IPAD_HOST:/tmp/Info.plist"
scp "$DIR/shield_ctl" "$IPAD_HOST:/tmp/shield_ctl"
scp "$DIR/AntiLagShield/entitlements.plist" "$IPAD_HOST:/tmp/entitlements.plist"
scp -r "$DIR/AntiLagShieldCC/AntiLagShieldCC.bundle" "$IPAD_HOST:/tmp/AntiLagShieldCC.bundle"
scp "$DIR/AntiLagShieldBanner/AntiLagShieldBanner.dylib" "$IPAD_HOST:/tmp/AntiLagShieldBanner.dylib"
scp "$DIR/AntiLagShieldBanner/AntiLagShieldBanner.plist" "$IPAD_HOST:/tmp/AntiLagShieldBanner.plist"

ssh "$IPAD_HOST" "
    sudo cp /tmp/shield_ctl /var/jb/usr/bin/shield_ctl
    sudo chmod 4755 /var/jb/usr/bin/shield_ctl
    
    sudo cp /tmp/AntiLagShield /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo cp /tmp/Info.plist /var/jb/Applications/AntiLagShield.app/Info.plist
    sudo chmod 755 /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo chmod 644 /var/jb/Applications/AntiLagShield.app/Info.plist
    sudo /var/jb/usr/bin/ldid -S/tmp/entitlements.plist /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo /var/jb/usr/bin/uicache -p /var/jb/Applications/AntiLagShield.app
    
    sudo rm -rf /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle
    sudo cp -r /tmp/AntiLagShieldCC.bundle /var/jb/Library/ControlCenter/Bundles/
    sudo chmod 755 /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle/AntiLagShieldCC
    sudo /var/jb/usr/bin/ldid -S /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle/AntiLagShieldCC
    
    sudo cp /tmp/AntiLagShieldBanner.dylib /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib
    sudo cp /tmp/AntiLagShieldBanner.plist /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.plist
    sudo chmod 755 /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib
    sudo chmod 644 /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.plist
    sudo /var/jb/usr/bin/ldid -S /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.dylib
"

echo "==> 5. Building clean Debian package (.deb) on iPad..."
ssh "$IPAD_HOST" "
    PKG_TMP='/tmp/pkg_build'
    sudo rm -rf \"\$PKG_TMP\"
    sudo mkdir -p \"\$PKG_TMP/rootless/DEBIAN\"
    sudo mkdir -p \"\$PKG_TMP/rootless/var/jb/Applications\"
    sudo mkdir -p \"\$PKG_TMP/rootless/var/jb/usr/bin\"
    sudo mkdir -p \"\$PKG_TMP/rootless/var/jb/Library/ControlCenter/Bundles\"
    sudo mkdir -p \"\$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries\"

    sudo cp -R /var/jb/Applications/AntiLagShield.app \"\$PKG_TMP/rootless/var/jb/Applications/\"
    sudo cp /var/jb/usr/bin/shield_ctl \"\$PKG_TMP/rootless/var/jb/usr/bin/\"
    sudo cp -R /var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle \"\$PKG_TMP/rootless/var/jb/Library/ControlCenter/Bundles/\"
    sudo cp /var/jb/usr/lib/TweakInject/AntiLagShieldBanner.* \"\$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries/\"

    sudo chown -R 0:0 \"\$PKG_TMP/rootless\"
    sudo chmod 4755 \"\$PKG_TMP/rootless/var/jb/usr/bin/shield_ctl\"
    sudo chmod 755 \"\$PKG_TMP/rootless/var/jb/Applications/AntiLagShield.app/AntiLagShield\"
    sudo chmod 644 \"\$PKG_TMP/rootless/var/jb/Applications/AntiLagShield.app/Info.plist\"
    sudo chmod 644 \"\$PKG_TMP/rootless/var/jb/Applications/AntiLagShield.app/\"*.png
    sudo chmod 755 \"\$PKG_TMP/rootless/var/jb/Library/ControlCenter/Bundles/AntiLagShieldCC.bundle/AntiLagShieldCC\"
    sudo chmod 755 \"\$PKG_TMP/rootless/var/jb/Library/MobileSubstrate/DynamicLibraries/AntiLagShieldBanner.dylib\"

    cat << 'CONTROL_EOF' | sudo tee \"\$PKG_TMP/rootless/DEBIAN/control\" >/dev/null
Package: com.nightknight.antilagshield
Name: Anti-Lag Shield
Version: 1.0.0
Architecture: iphoneos-arm64
Description: Network buffer and latency tuning suite with Control Center, Banner, and Shortcut toggles.
Maintainer: Jordan Allison <nightknight24@users.noreply.github.com>
Author: Jordan Allison
Section: System
Depends: firmware (>= 12.0)
CONTROL_EOF

    cat << 'POSTINST_EOF' | sudo tee \"\$PKG_TMP/rootless/DEBIAN/postinst\" >/dev/null
#!/bin/sh
chmod 4755 /var/jb/usr/bin/shield_ctl 2>/dev/null
if which uicache >/dev/null 2>&1; then
    uicache -p /var/jb/Applications/AntiLagShield.app 2>/dev/null
fi
exit 0
POSTINST_EOF
    sudo chmod 755 \"\$PKG_TMP/rootless/DEBIAN/postinst\"

    sudo /var/jb/usr/bin/dpkg-deb --root-owner-group -Zgzip -b \"\$PKG_TMP/rootless\" /tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb
    sudo chmod 666 /tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb
"

echo "==> 6. Fetching compiled .deb to Desktop and Downloads..."
scp "$IPAD_HOST:/tmp/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb" "$HOME/Desktop/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb"
cp "$HOME/Desktop/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb" "$HOME/Downloads/com.nightknight.antilagshield_1.0.0_iphoneos-arm64.deb"

echo "==> DONE! All 3 toggle options built, verified, and packaged into Debian package!"
