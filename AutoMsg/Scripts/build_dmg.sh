#!/bin/bash
# Builds AutoMsg.app, ad-hoc signs it, and packages it as AutoMsg.dmg ready for distribution.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/AutoMsg.app"
DMG_PATH="$PROJECT_DIR/AutoMsg.dmg"
STAGING="$PROJECT_DIR/.dmg_staging"

cd "$PROJECT_DIR"

echo "==> Building AutoMsg.app"
bash "$PROJECT_DIR/build.sh"

echo "==> Ad-hoc signing the app"
codesign --force --deep --sign - "$APP_BUNDLE"

# Verify
codesign --verify --deep --strict "$APP_BUNDLE" && echo "  signature OK"

echo "==> Preparing DMG staging area"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Optional background image / volume icon could go here
# cp "$PROJECT_DIR/Assets/dmg_background.png" "$STAGING/.background.png"

echo "==> Creating DMG"
hdiutil create \
    -volname "AutoMsg" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"

rm -rf "$STAGING"

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "DMG created: $DMG_PATH ($SIZE)"
echo ""
echo "To install: double-click the DMG, drag AutoMsg to Applications, eject."
echo ""
echo "Note: This is ad-hoc signed. Users will see a Gatekeeper warning on first launch."
echo "      They need to right-click AutoMsg.app → Open, then click Open in the dialog."
echo "      Or: System Settings > Privacy & Security > 'Open Anyway' button."
