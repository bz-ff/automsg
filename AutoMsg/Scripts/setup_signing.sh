#!/bin/bash
# One-time setup: create a stable self-signed code-signing identity so AutoMsg
# rebuilds keep their Full Disk Access / Contacts / Local Network grants.
#
# WHY: macOS TCC (privacy permissions) keys grants to the app's code-signing
# identity. Ad-hoc signing (`codesign -s -`) produces a different hash every
# build, so each rebuild looks like a brand-new app and macOS asks for
# permissions again. Signing with a STABLE identity fixes this.
#
# This script walks you through creating the identity using the built-in
# macOS Certificate Assistant (a one-time, ~30-second process).
set -e

CERT_NAME="AutoMsg Self-Signed"

if security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
    echo "Identity '$CERT_NAME' already exists. You're set."
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

cat <<'EOF'
============================================================
AutoMsg Code Signing — One-Time Setup
============================================================

To stop macOS from asking you to re-grant Full Disk Access on every
rebuild, we need a stable self-signed code-signing identity.

The most reliable way to create one is via macOS Certificate Assistant.
I'll open it for you. Follow these steps:

  1. Choose menu: Keychain Access → Certificate Assistant →
     Create a Certificate...
     (I'll open this menu for you in 3 seconds.)

  2. In the dialog:
     - Name:                 AutoMsg Self-Signed
     - Identity Type:        Self Signed Root
     - Certificate Type:     Code Signing
     - Check "Let me override defaults"
     - Click Continue → Continue → set validity to 3650 days
     - Click Continue through the rest, accept defaults
     - Final dialog: choose "login" keychain

  3. Once created, return here and press ENTER to verify.

Press ENTER to open Keychain Access...
EOF
read -r

# Open Keychain Access, then trigger the menu via osascript
open -a "Keychain Access"
sleep 2

osascript <<'OSA' 2>/dev/null || true
tell application "Keychain Access" to activate
delay 1
tell application "System Events"
    tell process "Keychain Access"
        click menu item "Create a Certificate..." of menu 1 of menu item "Certificate Assistant" of menu 1 of menu bar item "Keychain Access" of menu bar 1
    end tell
end tell
OSA

echo ""
echo "When you're done creating the certificate, press ENTER to verify..."
read -r

if security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
    echo ""
    echo "✓ Identity '$CERT_NAME' is now available for signing."
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    echo ""
    echo "From now on, build.sh and build_dmg.sh will use this identity"
    echo "automatically. Your Full Disk Access grant will persist across rebuilds."
    echo ""
    echo "IMPORTANT: After the next build, you'll need to grant Full Disk Access"
    echo "ONE more time (the new signature differs from the previous ad-hoc one)."
    echo "After that, the grant will stick across all future rebuilds."
else
    echo ""
    echo "⚠ Could not find '$CERT_NAME' as a code-signing identity yet."
    echo "  Open Keychain Access, find the cert, and verify:"
    echo "    - It's in the 'login' keychain"
    echo "    - Its trust settings include 'Code Signing: Always Trust'"
    echo "      (right-click → Get Info → Trust → Code Signing → Always Trust)"
    echo "  Then re-run this script."
fi
