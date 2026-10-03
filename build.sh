#!/bin/sh
# Builds build/SameSide.app for Apple silicon and Intel, macOS 14 or later.
# Needs only the Command Line Tools, not Xcode.
#   SIGN_ID="SameSide Dev" ./build.sh   sign with the project certificate, so the Accessibility
#                                       permission survives rebuilds and updates (ad-hoc loses it)
#   ./build.sh dmg                      also make build/SameSide.dmg for a GitHub release
#                                       (Finder lays out the window, so allow Terminal to control Finder once)
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 sources/Picker.swift tests/main.swift -o build/tests
./build/tests
APP=build/SameSide.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" sources/*.swift -o "build/SameSide-$arch"
done
lipo -create build/SameSide-arm64 build/SameSide-x86_64 -output "$APP/Contents/MacOS/SameSide"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"
[ "$1" = dmg ] || exit 0

# Installer window: app on the left, Applications on the right, arrow background, no toolbar.
# Finder writes the layout itself (dmgbuild-style .DS_Store files lose the background on macOS 15+).
hdiutil detach /Volumes/SameSide -quiet 2>/dev/null || true
rm -rf build/dmg build/rw.dmg
mkdir -p build/dmg/.background
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
cp resources/dmg-background.tiff build/dmg/.background/background.tiff
cp resources/AppIcon.icns build/dmg/.VolumeIcon.icns
hdiutil create -quiet -volname SameSide -srcfolder build/dmg -fs HFS+ -format UDRW -ov build/rw.dmg
hdiutil attach -quiet -readwrite -noverify -noautoopen build/rw.dmg
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 /Volumes/SameSide  # use .VolumeIcon.icns
osascript <<'EOF'
tell application "Finder"
    tell disk "SameSide"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 860, 520}
        set options to icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "SameSide.app" of container window to {165, 190}
        set position of item "Applications" of container window to {495, 190}
        set extension hidden of item "SameSide.app" to true
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
sync
hdiutil detach -quiet /Volumes/SameSide
hdiutil convert -quiet build/rw.dmg -format UDZO -ov -o build/SameSide.dmg
rm build/rw.dmg
echo "Built build/SameSide.dmg"
