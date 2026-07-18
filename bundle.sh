#!/bin/zsh
# Build SpeakDuck.app — a proper menu-bar app bundle so it can request the
# system-audio-recording permission the bare CLI couldn't.
set -e
cd "$(dirname "$0")"

# App icon: rasterize the duck SVG → AppIcon.icns via QuickLook (no external SVG
# tools needed). Regenerate only when the SVG is newer or the icns is missing.
ICON_SVG="speak-duck-cyan.svg"
if [ ! -f AppIcon.icns ] || [ "$ICON_SVG" -nt AppIcon.icns ]; then
  echo "Rendering AppIcon.icns from $ICON_SVG…"
  TMPI="$(mktemp -d)"
  qlmanage -t -s 1024 -o "$TMPI" "$ICON_SVG" >/dev/null 2>&1 || true
  BIG="$TMPI/$ICON_SVG.png"
  if [ -f "$BIG" ]; then
    ISET="$TMPI/AppIcon.iconset"; mkdir -p "$ISET"
    for s in 16 32 128 256 512; do
      sips -z $s $s             "$BIG" --out "$ISET/icon_${s}x${s}.png"    >/dev/null 2>&1
      sips -z $((s*2)) $((s*2)) "$BIG" --out "$ISET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ISET" -o AppIcon.icns && echo "  built AppIcon.icns"
  else
    echo "  (icon render failed — building without a custom icon)"
  fi
  rm -rf "$TMPI"
fi

swiftc Engine.swift SpeakDuckApp.swift -o SpeakDuck

# Assemble and sign OUTSIDE this (Syncthing-synced) folder: the sync daemon tags
# files with xattrs mid-build, which codesign rejects as "detritus". Build in a
# temp dir, sign there, then move the finished bundle back into place.
BUILDDIR="$(mktemp -d)"
APP="$BUILDDIR/SpeakDuck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv SpeakDuck "$APP/Contents/MacOS/SpeakDuck"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SpeakDuck</string>
  <key>CFBundleDisplayName</key><string>speak-duck</string>
  <key>CFBundleIdentifier</key><string>com.rhklite.speakduck</string>
  <key>CFBundleExecutable</key><string>SpeakDuck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.3</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>speak-duck reads system audio levels to duck background music while Spoken Content speaks.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>speak-duck reads system audio levels to duck background music while Spoken Content speaks.</string>
</dict>
</plist>
PLIST

xattr -cr "$APP"   # strip Finder info / resource forks; codesign rejects them

# --- Stable code signing: sign with a fixed self-signed identity so the app's
# designated requirement stays constant across rebuilds, preserving TCC grants
# (notably Accessibility for pause mode). Falls back to ad-hoc if absent.
SIGN_KC="$HOME/Library/Keychains/speakduck-signing.keychain-db"
SIGN_CN="SpeakDuck Local Signing"
SIGN_PWF="$HOME/.speakduck-signing-pw"
SIGN_HASH=""
if [ -f "$SIGN_KC" ] && [ -f "$SIGN_PWF" ]; then
  security unlock-keychain -p "$(cat "$SIGN_PWF")" "$SIGN_KC" 2>/dev/null || true
  SIGN_HASH=$(security find-identity -p codesigning "$SIGN_KC" | grep "$SIGN_CN" | grep -oE '[0-9A-F]{40}' | head -1)
fi
if [ -n "$SIGN_HASH" ]; then
  codesign --force --deep --sign "$SIGN_HASH" --keychain "$SIGN_KC" "$APP" && echo "(signed: $SIGN_CN)"
else
  codesign --force --deep --sign - "$APP" 2>/dev/null; echo "(ad-hoc signed — stable identity missing; pause perms reset each build)"
fi
codesign --verify --strict "$APP" || { echo "SIGNATURE VERIFY FAILED"; exit 1; }

# Move the finished, signed bundle back into the repo dir.
rm -rf "SpeakDuck.app"
mv "$APP" "SpeakDuck.app"
rmdir "$BUILDDIR" 2>/dev/null || true
APP="SpeakDuck.app"
echo "Built $APP — launch with:  open $APP"
