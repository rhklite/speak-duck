#!/bin/zsh
# Build a pretty drag-to-install DMG: app on the left, an arrow, Applications on
# the right, over a generated background. Run AFTER ./bundle.sh has built the app.
# The Finder-layout step needs one-time Automation permission for your terminal
# (System Settings ▸ Privacy & Security ▸ Automation). If denied, you still get a
# working DMG, just without the arrow background — re-run after approving.
set -e
cd "$(dirname "$0")"
APP="SpeakDuck.app"; VOL="SpeakDuck"; DMG="SpeakDuck.dmg"
[ -d "$APP" ] || { echo "Build the app first:  ./bundle.sh"; exit 1; }

WORK="$(mktemp -d)"
trap 'hdiutil detach "/Volumes/$VOL" 2>/dev/null; rm -rf "$WORK"' EXIT

# 1) Render the background (540x380) with an arrow from app -> Applications.
cat > "$WORK/mkbg.swift" <<'SWIFT'
import AppKit
let w = 540.0, h = 380.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
let y = 210.0
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 212, y: y)); shaft.line(to: NSPoint(x: 330, y: y))
shaft.lineWidth = 6; shaft.lineCapStyle = .round
NSColor(calibratedWhite: 0.64, alpha: 1).setStroke(); shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 342, y: y)); head.line(to: NSPoint(x: 322, y: y + 13)); head.line(to: NSPoint(x: 322, y: y - 13)); head.close()
NSColor(calibratedWhite: 0.64, alpha: 1).setFill(); head.fill()
let p = NSMutableParagraphStyle(); p.alignment = .center
let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1), .paragraphStyle: p]
("To install, drag SpeakDuck onto the Applications folder" as NSString)
    .draw(in: NSRect(x: 20, y: 312, width: w - 40, height: 22), withAttributes: a)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swift "$WORK/mkbg.swift" "$WORK/bg.png"

# 2) Stage contents (app + Applications shortcut + hidden background).
STAGE="$WORK/stage"; mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP"   # ditto preserves the Icon resource fork (cp -R can drop custom-icon metadata)
cp "$WORK/bg.png" "$STAGE/.background/bg.png"
ln -s /Applications "$STAGE/Applications"

# 3) Read-write DMG, mount it.
hdiutil detach "/Volumes/$VOL" 2>/dev/null || true
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" >/dev/null
hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" >/dev/null
sleep 1

# 4) Finder layout (background + icon positions). Best-effort.
osascript <<APPLESCRIPT 2>/dev/null || echo "(Finder layout skipped — approve Automation for your terminal and re-run for the arrow view)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 522}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 96
    set background picture of vo to file ".background:bg.png"
    set position of item "$APP" of container window to {135, 170}
    set position of item "Applications" of container window to {405, 170}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync; sleep 1
sync; sleep 1

# Strip the com.apple.FinderInfo xattr that Finder writes onto the bundle during
# the icon-layout step above. It invalidates the app's code signature, so the
# shipped DMG would otherwise fail `codesign --verify` and macOS reports the app
# as "damaged" even after the user clears the download quarantine. Icon positions
# live in the volume's .DS_Store (not the app's FinderInfo), so layout is intact.
xattr -cr "/Volumes/$VOL/$APP"
codesign --verify --strict "/Volumes/$VOL/$APP" \
  || { echo "Signature invalid in packaged app — aborting"; exit 1; }

hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1

# NOTE: Do NOT set the com.apple.FinderInfo custom-icon bit here. This app
# provides its icon via CFBundleIconFile (Resources/AppIcon.icns). Forcing the
# custom-icon flag with no Icon\\r resource makes Finder render the app as a
# plain folder in the DMG. LaunchServices uses AppIcon.icns automatically.

# 5) Compress to a distributable read-only DMG.
rm -f "$DMG"
hdiutil convert "$WORK/rw.dmg" -format UDZO -o "$DMG" >/dev/null
echo "Built $DMG"
