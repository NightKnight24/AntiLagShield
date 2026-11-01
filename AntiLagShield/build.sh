#!/bin/bash
# ==============================================================================
# 🛡️ Anti-Lag Shield Pro Build & Deploy Script
# Compiles UIKit binary using iPhoneOS SDK, packages .app bundle,
# transfers to iPad over Wi-Fi, signs with ldid, and registers via uicache.
# ==============================================================================

set -e

IPAD_HOST="${1:-ipad}"
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Compiling AntiLagShield for arm64..."
xcrun -sdk iphoneos clang -arch arm64 -fobjc-arc \
    -isysroot "$SDK_PATH" \
    -miphoneos-version-min=15.0 \
    -framework UIKit -framework Foundation \
    "$DIR/main.m" -o "$DIR/AntiLagShield.app/AntiLagShield"

echo "==> Deploying to iPad ($IPAD_HOST)..."
scp "$DIR/AntiLagShield.app/AntiLagShield" "$IPAD_HOST:/tmp/AntiLagShield"
scp "$DIR/../shield_ctl" "$IPAD_HOST:/tmp/shield_ctl"

ssh "$IPAD_HOST" "
    sudo cp /tmp/shield_ctl /var/jb/usr/bin/shield_ctl && sudo chmod 755 /var/jb/usr/bin/shield_ctl
    sudo cp /tmp/AntiLagShield /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo chmod 755 /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo /var/jb/usr/bin/ldid -S /var/jb/Applications/AntiLagShield.app/AntiLagShield
    sudo /var/jb/usr/bin/uicache -p /var/jb/Applications/AntiLagShield.app
"

echo "==> Successfully built and deployed Anti-Lag Shield Pro to iPad!"
