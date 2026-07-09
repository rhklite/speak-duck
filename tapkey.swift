// tapkey.swift — fire a single play/pause media key (software equivalent of the
// physical ▶❙❙ key). Build: swiftc tapkey.swift -o tapkey   Run: ./tapkey
import AppKit
import ApplicationServices

let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
print("accessibility trusted = \(trusted)")
if !trusted {
    print("→ Grant your terminal app in System Settings ▸ Privacy & Security ▸ Accessibility, then rerun.")
}

func post(_ key: Int32, _ down: Bool) {
    let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
    let data1 = (Int(key) << 16) | (down ? 0xA00 : 0xB00)
    NSEvent.otherEvent(
        with: .systemDefined, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil,
        subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
}
post(16, true); post(16, false)   // 16 = NX_KEYTYPE_PLAY
print("sent play/pause toggle")
