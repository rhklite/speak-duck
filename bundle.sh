#!/bin/zsh
# Build SpeakDuck.app — a proper menu-bar app bundle so it can request the
# system-audio-recording permission the bare CLI couldn't.
set -e
cd "$(dirname "$0")"

swiftc Engine.swift SpeakDuckApp.swift -o SpeakDuck

APP="SpeakDuck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv SpeakDuck "$APP/Contents/MacOS/SpeakDuck"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SpeakDuck</string>
  <key>CFBundleDisplayName</key><string>speak-duck</string>
  <key>CFBundleIdentifier</key><string>com.rhklite.speakduck</string>
  <key>CFBundleExecutable</key><string>SpeakDuck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>speak-duck reads system audio levels to duck background music while Spoken Content speaks.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>speak-duck reads system audio levels to duck background music while Spoken Content speaks.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(codesign skipped)"
echo "Built $APP — launch with:  open $APP"
